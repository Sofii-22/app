// Android / iOS / desktop: mantiene los archivos originales en disco.
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<String> rutaNuevaGrabacion(DateTime fecha) async {
  final carpeta = await getTemporaryDirectory();
  return '${carpeta.path}/audio_${fecha.millisecondsSinceEpoch}.m4a';
}

Future<int> tamano(String ruta) => File(ruta).length();

Future<void> borrar(String ruta) async {
  final archivo = File(ruta);
  if (await archivo.exists()) await archivo.delete();
}

Future<Uint8List?> bytesParaSubir(String ruta) async => null;

UploadTask subir(
    Reference ref, String ruta, SettableMetadata metadata, Uint8List? bytes) {
  return ref.putFile(File(ruta), metadata);
}

Future<String> prepararAudioRemoto(Reference ref, String id) async {
  final carpeta = await getTemporaryDirectory();
  final ext = ref.name.toLowerCase().endsWith('.webm') ? 'webm' : 'm4a';
  final nombre = id.hashCode.toUnsigned(32).toRadixString(16);
  final destino = File('${carpeta.path}/reproducir_$nombre.$ext');
  if (!await destino.exists() || await destino.length() == 0) {
    final resultado = await ref.writeToFile(destino);
    if (resultado.state != TaskState.success || await destino.length() == 0) {
      throw StateError('No se completó la descarga del audio.');
    }
  }
  return destino.path;
}

Future<void> compartir(String titulo, String url) async {
  final cliente = HttpClient();
  try {
    final solicitud = await cliente.getUrl(Uri.parse(url));
    final respuesta = await solicitud.close();
    if (respuesta.statusCode != HttpStatus.ok) {
      throw HttpException('Falló la descarga: ${respuesta.statusCode}');
    }
    final carpeta = await getTemporaryDirectory();
    final ext = Uri.tryParse(url)?.path.toLowerCase().contains('.webm') == true
        ? 'webm' : 'm4a';
    final file = File('${carpeta.path}/compartir_${DateTime.now().millisecondsSinceEpoch}.$ext');
    final sink = file.openWrite();
    try { await sink.addStream(respuesta); } finally { await sink.close(); }
    await SharePlus.instance.share(ShareParams(
      title: titulo, text: titulo,
      files: [XFile(file.path, mimeType: ext == 'webm' ? 'audio/webm' : 'audio/mp4')],
    ));
  } finally { cliente.close(force: true); }
}
