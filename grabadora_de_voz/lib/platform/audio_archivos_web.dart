// Chrome: record.stop() devuelve blob: URL. Se lee como bytes para Storage.
// Este archivo se importa SOLAMENTE al compilar para navegador.
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';

Future<String> rutaNuevaGrabacion(DateTime fecha) async {
  // record_web ignora el nombre y devuelve una URL blob al detenerse.
  return 'audio_${fecha.millisecondsSinceEpoch}.webm';
}

Future<Uint8List> _leer(String url) async {
  final respuesta = await http.get(Uri.parse(url));
  if (respuesta.statusCode != 200) {
    throw StateError('No se pudo leer el audio del navegador (${respuesta.statusCode}).');
  }
  return respuesta.bodyBytes;
}

Future<int> tamano(String ruta) async => (await _leer(ruta)).length;

Future<void> borrar(String ruta) async {
  // La URL blob deja de estar disponible al cerrar/recargar la página.
  // No se utiliza dart:io en el navegador.
}

Future<Uint8List?> bytesParaSubir(String ruta) => _leer(ruta);

UploadTask subir(
    Reference ref, String ruta, SettableMetadata metadata, Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) {
    throw StateError('La grabación web está vacía.');
  }
  return ref.putData(bytes, metadata);
}

Future<String> prepararAudioRemoto(Reference ref, String id) {
  // Un reproductor HTML puede abrir la URL HTTPS de Storage directamente.
  return ref.getDownloadURL();
}

Future<void> compartir(String titulo, String url) async {
  final respuesta = await http.get(Uri.parse(url));
  if (respuesta.statusCode != 200) {
    throw StateError('No se pudo descargar el audio (${respuesta.statusCode}).');
  }
  final esWebm = Uri.decodeFull(url).contains('.webm');
  await SharePlus.instance.share(ShareParams(
    title: titulo, text: titulo,
    files: [XFile.fromData(
      respuesta.bodyBytes,
      mimeType: esWebm ? 'audio/webm' : 'audio/mp4',
      name: esWebm ? '$titulo.webm' : '$titulo.m4a',
    )],
  ));
}
