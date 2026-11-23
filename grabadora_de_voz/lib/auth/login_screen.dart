import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../theme/theme.dart';

const Color _azul = AppColors.primary500;
const Color _blanco = Colors.white;
const Color _grisCampo = Color(0xFFF0F0F0);
const Color _texto = AppColors.gs900;
const Color _textoSecundario = AppColors.gs600;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final correoController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  bool cargando = false;
  bool mostrarPassword = false;

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> iniciarSesionCorreo() async {
    if (cargando || !formKey.currentState!.validate()) return;
    setState(() => cargando = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: correoController.text.trim(),
        password: passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      _aviso(_mensajeFirebase(e.code));
    } catch (e) {
      _aviso('No se pudo iniciar sesión: $e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  // Google en Chrome utiliza Firebase Auth con una ventana emergente.
  // Android conserva GoogleSignIn nativo y el flujo que ya funcionaba.
  Future<void> iniciarSesionGoogle() async {
    if (cargando) return;
    setState(() => cargando = true);
    try {
      if (kIsWeb) {
        final proveedor = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(proveedor);
      } else {
        final googleUser = await GoogleSignIn.instance.authenticate();
        final googleAuth = googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _aviso('Error al ingresar con Google: $e');
      }
    } on FirebaseAuthException catch (e) {
      // Cerrar la ventana de Google no debe mostrarse como un error.
      if (e.code != 'popup-closed-by-user' &&
          e.code != 'cancelled-popup-request') {
        _aviso(_mensajeFirebase(e.code));
      }
    } catch (e) {
      _aviso('No se pudo ingresar con Google: $e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  void dispose() {
    correoController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tecladoAbierto = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Theme(
      data: _temaAcceso(context),
      child: Scaffold(
        backgroundColor: _blanco,
        resizeToAvoidBottomInset: true,
        // Sin AppBar ni botón de retroceso.
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight > 48
                      ? constraints.maxHeight - 48
                      : 0.0,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: tecladoAbierto ? 8 : 90),
                      const Center(child: _ImagenPerfilAcceso()),
                      SizedBox(height: tecladoAbierto ? 24 : 52),
                      _CampoAcceso(
                        controller: correoController,
                        hint: 'Email',
                        icono: Icons.mail_outline,
                        tipoTeclado: TextInputType.emailAddress,
                        accionTeclado: TextInputAction.next,
                        validator: (valor) {
                          if (valor == null || valor.trim().isEmpty) {
                            return 'Ingresa tu correo';
                          }
                          if (!valor.contains('@') || !valor.contains('.')) {
                            return 'Ingresa un correo válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _CampoAcceso(
                        controller: passwordController,
                        hint: 'Contraseña',
                        icono: Icons.lock_outline,
                        ocultar: !mostrarPassword,
                        accionTeclado: TextInputAction.done,
                        onSubmitted: (_) => iniciarSesionCorreo(),
                        suffix: IconButton(
                          tooltip: mostrarPassword
                              ? 'Ocultar contraseña'
                              : 'Mostrar contraseña',
                          onPressed: () => setState(
                            () => mostrarPassword = !mostrarPassword,
                          ),
                          icon: Icon(
                            mostrarPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: _texto,
                          ),
                        ),
                        validator: (valor) => valor == null || valor.isEmpty
                            ? 'Ingresa tu contraseña'
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: cargando
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const RecuperarPasswordScreen(),
                                    ),
                                  ),
                          child: Text(
                            '¿Olvidaste tu contraseña?',
                            style: AppTypography.b2.copyWith(color: _texto),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _BotonPrincipal(
                        texto: 'Iniciar sesión',
                        cargando: cargando,
                        onPressed: cargando ? null : iniciarSesionCorreo,
                      ),
                      const SizedBox(height: 16),
                      _BotonBlanco(
                        texto: 'Registrarse',
                        onPressed: cargando
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const RegistroScreen(),
                                  ),
                                ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: cargando ? null : iniciarSesionGoogle,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _blanco,
                            foregroundColor: _texto,
                            side: const BorderSide(
                              color: Color(0xFFD5D5D5),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const _IconoGoogle(),
                              const SizedBox(width: 12),
                              Text(
                                'Continuar con Google',
                                style: AppTypography.b2.copyWith(color: _texto),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (cargando) ...[
                        const SizedBox(height: 20),
                        const Center(
                          child: CircularProgressIndicator(color: _azul),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final correo = TextEditingController();
  final password = TextEditingController();
  final confirmar = TextEditingController();
  final formulario = GlobalKey<FormState>();
  bool cargando = false;
  bool mostrarPassword = false;

  Future<void> registrar() async {
    if (cargando || !formulario.currentState!.validate()) return;
    setState(() => cargando = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: correo.text.trim(),
        password: password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeFirebase(e.code))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo registrar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  void dispose() {
    correo.dispose();
    password.dispose();
    confirmar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _temaAcceso(context),
      child: Scaffold(
        backgroundColor: _blanco,
        appBar: AppBar(
          backgroundColor: _blanco,
          surfaceTintColor: _blanco,
          foregroundColor: _texto,
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Form(
              key: formulario,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: _ImagenPerfilAcceso()),
                  const SizedBox(height: 34),
                  Text(
                    'Crear una cuenta',
                    textAlign: TextAlign.center,
                    style: AppTypography.h5.copyWith(
                      color: _texto,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _CampoAcceso(
                    controller: correo,
                    hint: 'Email',
                    icono: Icons.email_outlined,
                    tipoTeclado: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Ingresa tu correo';
                      }
                      if (!v.contains('@') || !v.contains('.')) {
                        return 'Correo no válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _CampoAcceso(
                    controller: password,
                    hint: 'Contraseña',
                    icono: Icons.lock_outline,
                    ocultar: !mostrarPassword,
                    suffix: IconButton(
                      onPressed: () => setState(
                        () => mostrarPassword = !mostrarPassword,
                      ),
                      icon: Icon(
                        mostrarPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _texto,
                      ),
                    ),
                    validator: (v) => v == null || v.length < 6
                        ? 'Usa al menos 6 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _CampoAcceso(
                    controller: confirmar,
                    hint: 'Confirmar contraseña',
                    icono: Icons.lock_outline,
                    ocultar: !mostrarPassword,
                    validator: (v) => v != password.text
                        ? 'Las contraseñas no coinciden'
                        : null,
                  ),
                  const SizedBox(height: 28),
                  _BotonPrincipal(
                    texto: 'Crear cuenta',
                    cargando: cargando,
                    onPressed: cargando ? null : registrar,
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: cargando
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text(
                      'Ya tengo una cuenta',
                      style: TextStyle(color: _azul),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RecuperarPasswordScreen extends StatefulWidget {
  const RecuperarPasswordScreen({super.key});

  @override
  State<RecuperarPasswordScreen> createState() =>
      _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen> {
  final correo = TextEditingController();
  final formulario = GlobalKey<FormState>();
  bool cargando = false;
  bool enviado = false;

  Future<void> recuperar() async {
    if (cargando || !formulario.currentState!.validate()) return;
    setState(() => cargando = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: correo.text.trim(),
      );
      if (mounted) setState(() => enviado = true);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeFirebase(e.code))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo enviar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  void dispose() {
    correo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _temaAcceso(context),
      child: Scaffold(
        backgroundColor: _blanco,
        appBar: AppBar(
          backgroundColor: _blanco,
          surfaceTintColor: _blanco,
          foregroundColor: _texto,
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Form(
              key: formulario,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: _ImagenPerfilAcceso()),
                  const SizedBox(height: 34),
                  Text(
                    'Recuperar contraseña',
                    textAlign: TextAlign.center,
                    style: AppTypography.h5.copyWith(
                      color: _texto,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    enviado
                        ? 'Si existe una cuenta asociada, recibirás un correo con las instrucciones.'
                        : 'Escribe tu correo electrónico para solicitar un enlace de recuperación.',
                    textAlign: TextAlign.center,
                    style: AppTypography.b2.copyWith(
                      color: _textoSecundario,
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (!enviado) ...[
                    _CampoAcceso(
                      controller: correo,
                      hint: 'Email',
                      icono: Icons.email_outlined,
                      tipoTeclado: TextInputType.emailAddress,
                      validator: (v) => v == null ||
                              v.trim().isEmpty ||
                              !v.contains('@')
                          ? 'Ingresa un correo válido'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    _BotonPrincipal(
                      texto: 'Enviar enlace',
                      cargando: cargando,
                      onPressed: cargando ? null : recuperar,
                    ),
                  ] else
                    _BotonPrincipal(
                      texto: 'Volver al inicio',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _ImagenPerfilAcceso extends StatelessWidget {
  const _ImagenPerfilAcceso();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 130,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F0F0),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person_outline_rounded,
        size: 65,
        color: AppColors.primary500,
      ),
    );
  }
}


class _CampoAcceso extends StatelessWidget {
  const _CampoAcceso({
    required this.controller,
    required this.hint,
    required this.icono,
    this.ocultar = false,
    this.tipoTeclado,
    this.accionTeclado,
    this.suffix,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icono;
  final bool ocultar;
  final TextInputType? tipoTeclado;
  final TextInputAction? accionTeclado;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: ocultar,
      keyboardType: tipoTeclado,
      textInputAction: accionTeclado,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      cursorColor: _azul,
      style: AppTypography.b2.copyWith(color: _texto),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.b2.copyWith(color: _textoSecundario),
        prefixIcon: Icon(icono, color: _texto, size: 22),
        suffixIcon: suffix,
        filled: true,
        fillColor: _grisCampo,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 21,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _azul, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.red, width: 1.8),
        ),
      ),
    );
  }
}

class _BotonPrincipal extends StatelessWidget {
  const _BotonPrincipal({
    required this.texto,
    required this.onPressed,
    this.cargando = false,
  });

  final String texto;
  final VoidCallback? onPressed;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 55,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _azul,
          foregroundColor: _blanco,
          disabledBackgroundColor: _azul.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: cargando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _blanco,
                ),
              )
            : Text(
                texto,
                style: AppTypography.butt.copyWith(color: _blanco),
              ),
      ),
    );
  }
}

class _BotonBlanco extends StatelessWidget {
  const _BotonBlanco({
    required this.texto,
    required this.onPressed,
  });

  final String texto;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: _blanco,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: _texto,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          texto,
          style: AppTypography.butt.copyWith(color: _texto),
        ),
      ),
    );
  }
}

class _IconoGoogle extends StatelessWidget {
  const _IconoGoogle();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 26,
      height: 30,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            color: Color(0xFF4285F4),
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -2,
          ),
        ),
      ),
    );
  }
}

ThemeData _temaAcceso(BuildContext context) {
  final actual = Theme.of(context);
  return actual.copyWith(
    scaffoldBackgroundColor: _blanco,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _azul,
      brightness: Brightness.light,
      primary: _azul,
      surface: _blanco,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: _azul,
      selectionColor: Color(0x661D5BF7),
      selectionHandleColor: _azul,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: _azul),
  );
}

String _mensajeFirebase(String codigo) {
  switch (codigo) {
    case 'invalid-email':
      return 'El correo electrónico no es válido.';
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
      return 'El correo o la contraseña son incorrectos.';
    case 'email-already-in-use':
      return 'Ya existe una cuenta con ese correo.';
    case 'weak-password':
      return 'La contraseña es demasiado débil.';
    case 'too-many-requests':
      return 'Demasiados intentos. Intenta más tarde.';
    case 'network-request-failed':
      return 'Comprueba tu conexión a internet.';
    case 'operation-not-allowed':
      return 'Este método de acceso no está habilitado en Firebase.';
    case 'auth-domain-config-required':
      return 'Configura el dominio autorizado en Firebase Authentication.';
    case 'unauthorized-domain':
      return 'Autoriza este dominio en Firebase Authentication.';
    case 'popup-blocked':
      return 'Chrome bloqueó la ventana de Google. Permite ventanas emergentes para este sitio.';
    default:
      return 'Ocurrió un error de autenticación: $codigo';
  }
}


