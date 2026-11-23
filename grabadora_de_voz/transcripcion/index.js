"use strict";

// Archivo: transcripcion/index.js
// Firebase Cloud Functions v2 (Node.js 20 o 22).
// Android: audio .m4a; Chrome: audio .webm.
// Requiere el secreto OPENAI_API_KEY en Firebase Secret Manager.

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const apiKey = defineSecret("OPENAI_API_KEY");
const MODELO = "gpt-4o-transcribe-diarize";
const MAX_AUDIO_BYTES = 20 * 1024 * 1024;

exports.transcribirGrabacion = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 300,
      memory: "512MiB",
      maxInstances: 5,
      secrets: [apiKey],
    },
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) {
        throw new HttpsError(
            "unauthenticated",
            "Debes iniciar sesión para transcribir.",
        );
      }

      const grabacionId = request.data && request.data.grabacionId;
      if (typeof grabacionId !== "string" ||
          !/^[A-Za-z0-9_-]{1,128}$/.test(grabacionId)) {
        throw new HttpsError(
            "invalid-argument",
            "Identificador de grabación inválido.",
        );
      }

      const documento = admin.firestore()
          .collection("grabaciones").doc(grabacionId);
      const snapshot = await documento.get();
      if (!snapshot.exists) {
        throw new HttpsError("not-found", "La grabación no existe.");
      }

      const datos = snapshot.data() || {};
      if (datos.usuarioId !== uid) {
        throw new HttpsError(
            "permission-denied",
            "Solo puedes transcribir tus propias grabaciones.",
        );
      }

      // La ruta debe ser la de esta grabación, no una URL local blob:.
      const ruta = datos.archivo;
      const rutaM4a = "grabaciones/" + grabacionId + ".m4a";
      const rutaWebm = "grabaciones/" + grabacionId + ".webm";
      const esM4a = ruta === rutaM4a;
      const esWebm = ruta === rutaWebm;

      if (!esM4a && !esWebm) {
        console.warn("Ruta de audio inválida", {
          grabacionId: grabacionId,
          rutaRecibida: typeof ruta === "string" ? ruta : null,
        });
        throw new HttpsError(
            "failed-precondition",
            "La grabación no tiene una ruta válida. " +
            "Comprueba el campo archivo en Firestore.",
        );
      }

      const extension = esWebm ? "webm" : "m4a";
      const tipo = esWebm ? "audio/webm" : "audio/mp4";

      try {
        const archivo = admin.storage().bucket().file(ruta);
        const existe = await archivo.exists();
        if (!existe[0]) {
          throw new HttpsError(
              "not-found",
              "El archivo no existe en Firebase Storage.",
          );
        }

        const respuestaMetadata = await archivo.getMetadata();
        const metadata = respuestaMetadata[0];
        const bytes = Number(metadata.size || 0);
        if (!Number.isFinite(bytes) || bytes <= 0) {
          throw new HttpsError(
              "failed-precondition",
              "El audio está vacío.",
          );
        }
        if (bytes > MAX_AUDIO_BYTES) {
          throw new HttpsError(
              "resource-exhausted",
              "El audio supera el límite de 20 MB.",
          );
        }

        const descargado = await archivo.download();
        const buffer = descargado[0];
        if (!buffer || buffer.length === 0) {
          throw new HttpsError(
              "failed-precondition",
              "No se pudo descargar el audio.",
          );
        }

        const formulario = new FormData();
        formulario.append("model", MODELO);
        formulario.append("response_format", "diarized_json");
        formulario.append("chunking_strategy", "auto");
        formulario.append(
            "file",
            new Blob([buffer], {type: tipo}),
            grabacionId + "." + extension,
        );

        const respuesta = await fetch(
            "https://api.openai.com/v1/audio/transcriptions",
            {
              method: "POST",
              headers: {
                Authorization: "Bearer " + apiKey.value(),
              },
              body: formulario,
              signal: AbortSignal.timeout(240000),
            },
        );

        if (!respuesta.ok) {
          const detalle = (await respuesta.text()).slice(0, 600);
          console.error("Error de OpenAI", {
            grabacionId: grabacionId,
            status: respuesta.status,
            detalle: detalle,
          });
          throw new HttpsError(
              "unavailable",
              "No se pudo transcribir (servicio " +
              respuesta.status + ").",
          );
        }

        const resultado = await respuesta.json();
        const segmentosCrudos = Array.isArray(resultado.segments) ?
          resultado.segments : [];
        const segmentos = segmentosCrudos.map((segmento) => {
          return {
            inicio: Number(segmento.start),
            fin: Number(segmento.end),
            hablante: String(
                segmento.speaker == null ?
                  "desconocido" : segmento.speaker,
            ).slice(0, 80),
            texto: String(
                segmento.text == null ? "" : segmento.text,
            ).trim(),
          };
        }).filter((segmento) => {
          return Number.isFinite(segmento.inicio) &&
              Number.isFinite(segmento.fin) &&
              segmento.inicio >= 0 &&
              segmento.fin >= segmento.inicio &&
              segmento.texto.length > 0;
        }).slice(0, 1500);

        if (segmentos.length === 0) {
          throw new HttpsError(
              "failed-precondition",
              "No se detectaron palabras con marcas de tiempo. " +
              "Revisa que el audio contenga voces.",
          );
        }

        const textoCompleto = segmentos.map((s) => s.texto)
            .join(" ").trim();

        // Actualiza solo los campos de la transcripción.
        // No borra banderas, favoritos ni nombres de hablantes.
        await documento.update({
          transcripcion: textoCompleto,
          segmentosTranscripcion: segmentos,
          transcripcionModelo: MODELO,
          transcripcionActualizadaEn:
              admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
          ok: true,
          segmentos: segmentos.length,
          formato: extension,
        };
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        console.error("No se pudo transcribir la grabación", {
          grabacionId: grabacionId,
          mensaje: error && error.message ?
            error.message : String(error),
        });
        throw new HttpsError(
            "internal",
            "No se pudo procesar el audio. " +
            "Consulta los registros de Firebase Functions.",
        );
      }
    },
);
