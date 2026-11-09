
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/theme.dart';

class PerfilScreen extends StatefulWidget {
  final VoidCallback onVolver;

  const PerfilScreen({
    super.key,
    required this.onVolver,
  });

  @override
  State<PerfilScreen> createState() =>
      _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _auth = FirebaseAuth.instance;
  final _picker = ImagePicker();

  String _nombre = '';
  String _apellidos = '';

  bool _notificaciones = true;
  bool _ocupado = false;

  User? get _usuario => _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final usuario = _usuario;
    if (usuario == null) return;

    final partes =
        (usuario.displayName ?? '').trim().split(' ');

    final nombre = partes.isNotEmpty ? partes.first : '';

    final apellidos = partes.length > 1
        ? partes.skip(1).join(' ')
        : '';

    if (mounted) {
      setState(() {
        _nombre = nombre;
        _apellidos = apellidos;
      });
    }

    try {
      final documento = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario.uid)
          .get();

      if (!mounted) return;

      final datos = documento.data();

      if (datos != null) {
        setState(() {
          _nombre = datos['nombre'] as String? ?? nombre;

          _apellidos =
              datos['apellidos'] as String? ?? apellidos;

          _notificaciones =
              datos['notificaciones'] as bool? ?? true;
        });
      }
    } catch (e) {
      debugPrint('No se cargaron preferencias: $e');
    }
  }

  void _mensaje(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            texto,
            style: AppTypography.b2,
          ),
        ),
      );
  }

  Future<void> _editarDato({
    required String titulo,
    required String valorActual,
    required bool editarNombre,
  }) async {
    final controller = TextEditingController(
      text: valorActual,
    );

    final resultado = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.gs50,
          title: Text(
            titulo,
            style: AppTypography.h6.copyWith(
              color: AppColors.gs900,
            ),
          ),
          content: TextField(
            controller: controller,
            maxLength: 60,
            textCapitalization:
                TextCapitalization.words,
            decoration: InputDecoration(
              hintText: titulo,
              filled: true,
              fillColor: AppColors.gs300,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  AppRadius.radiusm,
                ),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary500,
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  controller.text.trim(),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (resultado == null || resultado.isEmpty) {
      return;
    }

    final usuario = _usuario;
    if (usuario == null) return;

    final nuevoNombre =
        editarNombre ? resultado : _nombre;

    final nuevosApellidos =
        editarNombre ? _apellidos : resultado;

    setState(() {
      _ocupado = true;
    });

    try {
      await usuario.updateDisplayName(
        '$nuevoNombre $nuevosApellidos'.trim(),
      );

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario.uid)
          .set({
        'nombre': nuevoNombre,
        'apellidos': nuevosApellidos,
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _nombre = nuevoNombre;
        _apellidos = nuevosApellidos;
      });

      _mensaje('Información actualizada');
    } catch (e) {
      _mensaje('No se pudo guardar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
        });
      }
    }
  }

  Future<void> _cambiarFoto() async {
    if (_ocupado) return;

    try {
      final imagen = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 80,
      );

      if (imagen == null) return;

      final usuario = _usuario;
      if (usuario == null) return;

      setState(() {
        _ocupado = true;
      });

      final referencia = FirebaseStorage.instance
          .ref('perfiles/${usuario.uid}/foto.jpg');

      await referencia.putFile(
        File(imagen.path),
        SettableMetadata(
          contentType: 'image/jpeg',
        ),
      );

      final url = await referencia.getDownloadURL();

      await usuario.updatePhotoURL(url);
      await usuario.reload();

      if (!mounted) return;

      setState(() {});

      _mensaje('Foto de perfil actualizada');
    } catch (e) {
      _mensaje('No se pudo cambiar la foto: $e');
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
        });
      }
    }
  }

  Future<void> _mostrarEmail() async {
    final email = _usuario?.email ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.gs50,
          title: Text(
            'Correo electrónico',
            style: AppTypography.h6,
          ),
          content: Text(
            '$email\n\nEl cambio de correo requiere '
            'verificación y, según el proveedor, '
            'volver a autenticar la cuenta.',
            style: AppTypography.b2,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _cambiarContrasena() async {
    final usuario = _usuario;

    if (usuario == null || usuario.email == null) {
      _mensaje('No hay correo asociado a la cuenta.');
      return;
    }

    final tieneContrasena = usuario.providerData.any(
      (proveedor) => proveedor.providerId == 'password',
    );

    if (!tieneContrasena) {
      _mensaje(
        'Tu cuenta utiliza otro proveedor de acceso. '
        'Administra su contraseña desde ese proveedor.',
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.gs50,
          title: Text(
            'Cambiar contraseña',
            style: AppTypography.h6,
          ),
          content: Text(
            'Te enviaremos un correo para '
            'restablecer tu contraseña.',
            style: AppTypography.b2,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary500,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Enviar correo'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      await _auth.sendPasswordResetEmail(
        email: usuario.email!,
      );

      _mensaje('Revisa tu correo electrónico.');
    } catch (e) {
      _mensaje('No se pudo enviar el correo: $e');
    }
  }

  Future<void> _editarNotificaciones() async {
    final usuario = _usuario;
    if (usuario == null) return;

    bool valor = _notificaciones;

    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.gs50,
              title: Text(
                'Notificaciones',
                style: AppTypography.h6,
              ),
              content: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Permitir notificaciones',
                  style: AppTypography.b2,
                ),
                value: valor,
                activeTrackColor: AppColors.primary500,
                onChanged: (nuevoValor) {
                  setDialogState(() {
                    valor = nuevoValor;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        AppColors.primary500,
                  ),
                  onPressed: () {
                    Navigator.pop(dialogContext, valor);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (resultado == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario.uid)
          .set({
        'notificaciones': resultado,
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _notificaciones = resultado;
      });

      _mensaje('Preferencia guardada');
    } catch (e) {
      _mensaje('No se pudo guardar la preferencia: $e');
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.gs50,
          title: Text(
            'Cerrar sesión',
            style: AppTypography.h6,
          ),
          content: Text(
            '¿Quieres salir de tu cuenta?',
            style: AppTypography.b2,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                'Cerrar sesión',
                style: AppTypography.butt.copyWith(
                  color: AppFeedbackColors.error,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    setState(() {
      _ocupado = true;
    });

    try {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('Google Sign-Out: $e');
      }

      await _auth.signOut();

      // AuthGate debe detectar el cambio de sesión.
    } catch (e) {
      _mensaje('No se pudo cerrar sesión: $e');

      if (mounted) {
        setState(() {
          _ocupado = false;
        });
      }
    }
  }

  Widget _opcionPerfil(
    String titulo,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: AppGap.gaprelated,
      ),
      decoration: BoxDecoration(
        color: AppColors.gs300,
        borderRadius: BorderRadius.circular(
          AppRadius.radiuss,
        ),
      ),
      child: ListTile(
        onTap: _ocupado ? null : onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppPadding.paddingmd,
        ),
        title: Text(
          titulo,
          style: AppTypography.b2.copyWith(
            color: AppColors.gs900,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.gs700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = _usuario;

    final nombreCompleto =
        '$_nombre $_apellidos'.trim();

    final nombreVisible = nombreCompleto.isNotEmpty
        ? nombreCompleto
        : (usuario?.displayName ?? 'Mi usuario');

    final urlFoto = usuario?.photoURL;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppPadding.paddinglg,
        ),
        children: [
          IconButton(
            alignment: Alignment.centerLeft,
            onPressed: widget.onVolver,
            icon: const Icon(
              Icons.arrow_circle_left_outlined,
              color: AppColors.gs900,
            ),
          ),

          const SizedBox(
            height: AppGap.gapgroup,
          ),

          Text(
            'Mi Perfil',
            style: AppTypography.h5.copyWith(
              color: AppColors.gs900,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(
            height: AppGap.gapgroup,
          ),

          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 64,
                  backgroundColor: AppColors.gs300,
                  backgroundImage:
                      urlFoto != null && urlFoto.isNotEmpty
                          ? NetworkImage(urlFoto)
                          : null,
                  child: urlFoto == null || urlFoto.isEmpty
                      ? const Icon(
                          Icons.person_outline,
                          size: 56,
                          color: AppColors.gs600,
                        )
                      : null,
                ),

                Positioned(
                  right: AppSpacing.spacingy200,
                  bottom: 0,
                  child: InkWell(
                    onTap: _ocupado ? null : _cambiarFoto,
                    child: const CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          AppColors.primary100,
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        color: AppColors.gs900,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: AppGap.gapcomponent,
          ),

          Center(
            child: Text(
              nombreVisible,
              textAlign: TextAlign.center,
              style: AppTypography.s1.copyWith(
                color: AppColors.gs900,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          Center(
            child: Text(
              usuario?.email ?? 'Sin correo',
              textAlign: TextAlign.center,
              style: AppTypography.cptn.copyWith(
                color: AppColors.gs600,
              ),
            ),
          ),

          const SizedBox(
            height: AppGap.gapgroup,
          ),

          Text(
            'Información usuario',
            style: AppTypography.s1.copyWith(
              color: AppColors.gs900,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(
            height: AppGap.gaprelated,
          ),

          _opcionPerfil(
            'Nombre',
            () => _editarDato(
              titulo: 'Nombre',
              valorActual: _nombre,
              editarNombre: true,
            ),
          ),

          _opcionPerfil(
            'Apellido(s)',
            () => _editarDato(
              titulo: 'Apellido(s)',
              valorActual: _apellidos,
              editarNombre: false,
            ),
          ),

          _opcionPerfil(
            'Email',
            _mostrarEmail,
          ),

          const SizedBox(
            height: AppGap.gapcomponent,
          ),

          Text(
            'Cuenta',
            style: AppTypography.s1.copyWith(
              color: AppColors.gs900,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(
            height: AppGap.gaprelated,
          ),

          _opcionPerfil(
            'Cambiar contraseña',
            _cambiarContrasena,
          ),

          const SizedBox(
            height: AppGap.gapcomponent,
          ),

          Text(
            'Preferencias',
            style: AppTypography.s1.copyWith(
              color: AppColors.gs900,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(
            height: AppGap.gaprelated,
          ),

          _opcionPerfil(
            'Notificaciones',
            _editarNotificaciones,
          ),

          const SizedBox(
            height: AppGap.gapgroup,
          ),

          Center(
            child: TextButton(
              onPressed:
                  _ocupado ? null : _cerrarSesion,
              child: Text(
                'Cerrar sesión',
                style: AppTypography.s1.copyWith(
                  color: AppFeedbackColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: AppGap.gapsection,
          ),
        ],
      ),
    );
  }
}
