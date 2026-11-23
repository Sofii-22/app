import 'package:firebase_storage/firebase_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

const bool esWeb = true;
String get extensionAudio => 'webm';
String get mimeAudio => 'audio/webm';

Future<String> nuevaRutaAudio() async {
  // record_web devuelve una URL blob: al terminar la grabación.
  return 'comunidad_nueva_${DateTime.now().microsecondsSinceEpoch}.webm';
}
Future<List<int>> _leerBlob(String url) async {
  final respuesta = await http.get(Uri.parse(url));
  if (respuesta.statusCode != 200) {
    throw Exception('No se pudieron leer los datos del micrófono (${respuesta.statusCode}).');
  }
  return respuesta.bodyBytes;
}
Future<int> tamanoAudio(String ruta) async => (await _leerBlob(ruta)).length;
Future<void> borrarAudio(String ruta) async {
  // El navegador libera el blob cuando se cierra la página.
  // No existen rutas de archivos File() en Chrome.
}
Future<void> prepararAudioLocal(AudioPlayer player, String ruta) async {
  await player.setUrl(ruta);
}
Future<void> prepararAudioRemoto(AudioPlayer player, Reference ref, String clave) async {
  final url = await ref.getDownloadURL();
  await player.setUrl(url);
}
Future<void> subirAudio(Reference ref, String ruta) async {
  final respuesta = await http.get(Uri.parse(ruta));
  if (respuesta.statusCode != 200 || respuesta.bodyBytes.isEmpty) {
    throw Exception('El audio web está vacío o no se pudo leer.');
  }
  await ref.putData(
    respuesta.bodyBytes,
    SettableMetadata(contentType: mimeAudio),
  );
}
Future<void> compartirAudio(Reference ref, String titulo) async {
  final url = await ref.getDownloadURL();
  // El navegador puede compartir el enlace sin descargar un File local.
  await SharePlus.instance.share(ShareParams(title: titulo, text: '$titulo\n$url'));
}
