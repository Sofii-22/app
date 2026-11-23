import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const bool esWeb = false;
String get extensionAudio => 'm4a';
String get mimeAudio => 'audio/mp4';

Future<String> nuevaRutaAudio() async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/comunidad_nueva_${DateTime.now().microsecondsSinceEpoch}.m4a';
}
Future<int> tamanoAudio(String ruta) async {
  final file = File(ruta);
  if (!await file.exists()) return 0;
  return file.length();
}
Future<void> borrarAudio(String ruta) async {
  final file = File(ruta);
  if (await file.exists()) await file.delete();
}
Future<void> prepararAudioLocal(AudioPlayer player, String ruta) async {
  await player.setFilePath(ruta);
}
Future<void> prepararAudioRemoto(AudioPlayer player, Reference ref, String clave) async {
  final dir = await getTemporaryDirectory();
  final ext = ref.name.toLowerCase().endsWith('.webm') ? 'webm' : 'm4a';
  final destino = File('${dir.path}/comunidad_${clave.hashCode.toUnsigned(32)}.$ext');
  if (!await destino.exists() || await destino.length() == 0) {
    final tarea = await ref.writeToFile(destino).timeout(const Duration(seconds: 45));
    if (tarea.state != TaskState.success) throw Exception('Descarga incompleta');
  }
  if (await destino.length() == 0) throw Exception('El audio está vacío');
  await player.setFilePath(destino.path);
}
Future<void> subirAudio(Reference ref, String ruta) async {
  final archivo = File(ruta);
  if (!await archivo.exists() || await archivo.length() == 0) {
    throw Exception('La grabación no contiene audio');
  }
  await ref.putFile(archivo, SettableMetadata(contentType: mimeAudio));
}
Future<void> compartirAudio(Reference ref, String titulo) async {
  final dir = await getTemporaryDirectory();
  final ext = ref.name.toLowerCase().endsWith('.webm') ? 'webm' : 'm4a';
  final destino = File('${dir.path}/compartir_${DateTime.now().millisecondsSinceEpoch}.$ext');
  await ref.writeToFile(destino).timeout(const Duration(seconds: 45));
  await SharePlus.instance.share(ShareParams(
    title: titulo,
    text: titulo,
    files: [XFile(destino.path, mimeType: ext == 'webm' ? 'audio/webm' : 'audio/mp4')],
  ));
}
