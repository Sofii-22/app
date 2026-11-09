
import 'package:flutter/material.dart';

import '../theme/theme.dart';

// Esta clase representa una publicación de Comunidad.
// Cada publicación tiene un título, autor, duración,
// categoría, comentarios y cantidad de favoritos.

class PublicacionComunidad {
  final String titulo;
  final String autor;
  final String duracion;
  final String categoria;
  final int comentarios;
  final int favoritos;

  const PublicacionComunidad({
    required this.titulo,
    required this.autor,
    required this.duracion,
    required this.categoria,
    required this.comentarios,
    required this.favoritos,
  });
}

// StatefulWidget permite actualizar los filtros,
// el buscador y los favoritos de la interfaz.

class ComunidadScreen extends StatefulWidget {
  const ComunidadScreen({super.key});

  @override
  State<ComunidadScreen> createState() =>
      _ComunidadScreenState();
}

class _ComunidadScreenState
    extends State<ComunidadScreen> {

  // Guarda el texto que escribimos en el buscador.
  String _busqueda = '';

  // Guarda la categoría seleccionada.
  String _categoriaSeleccionada = 'Todos';

  // Orden actual de las publicaciones.
  String _orden = 'recientes';

  // Guarda cuáles publicaciones tienen "me gusta".
  // En esta versión funciona localmente.
  final Set<String> _favoritos = {};

  // Categorías que aparecen debajo del buscador.
  final List<String> _categorias = [
    'Todos',
    'Estudio',
    'Trabajo',
    'Ideas',
  ];

  // Datos de ejemplo basados en tu referencia visual.
  // Después podrán venir desde Firebase.

  final List<PublicacionComunidad> _publicaciones = [
    const PublicacionComunidad(
      titulo: 'Sesión de brainstorming',
      autor: 'María López',
      duracion: '01:24',
      categoria: 'Ideas',
      comentarios: 12,
      favoritos: 24,
    ),
    const PublicacionComunidad(
      titulo: 'Resumen del cliente',
      autor: 'Carlos Méndez',
      duracion: '02:18',
      categoria: 'Trabajo',
      comentarios: 8,
      favoritos: 16,
    ),
    const PublicacionComunidad(
      titulo: 'Notas de investigación',
      autor: 'Ana Torres',
      duracion: '03:05',
      categoria: 'Estudio',
      comentarios: 6,
      favoritos: 22,
    ),
    const PublicacionComunidad(
      titulo: 'Entrevista a usuario',
      autor: 'Javier Ruiz',
      duracion: '01:47',
      categoria: 'Trabajo',
      comentarios: 5,
      favoritos: 18,
    ),
  ];

  // Filtra los datos por nombre, autor y categoría.
  // También aplica el orden seleccionado.

  List<PublicacionComunidad> get _publicacionesFiltradas {
    final resultado = _publicaciones.where((publicacion) {

      final texto = _busqueda.toLowerCase();

      final coincideBusqueda =
          publicacion.titulo.toLowerCase().contains(texto) ||
          publicacion.autor.toLowerCase().contains(texto);

      final coincideCategoria =
          _categoriaSeleccionada == 'Todos' ||
          publicacion.categoria == _categoriaSeleccionada;

      return coincideBusqueda && coincideCategoria;
    }).toList();

    if (_orden == 'favoritos') {
      resultado.sort(
        (a, b) => b.favoritos.compareTo(a.favoritos),
      );
    }

    return resultado;
  }

  // Muestra mensajes breves para las funciones
  // que todavía no están conectadas a Firebase.

  void _mensaje(String texto) {
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

  // Crea las pestañas de Comunidad.
  // Utiliza la misma estructura que _pestana()
  // de tu pantalla Mis Grabaciones.

  Widget _pestanaComunidad(String titulo) {
    final seleccionada =
        _categoriaSeleccionada == titulo;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _categoriaSeleccionada = titulo;
          });
        },

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              titulo,
              style: AppTypography.s2.copyWith(
                color: AppColors.gs900,
                fontWeight: seleccionada
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),

            const SizedBox(
              height: AppGap.gaprelated,
            ),

            Container(
              height: AppSpacing.spacingy200,

              decoration: BoxDecoration(
                color: seleccionada
                    ? AppColors.primary500
                    : AppColors.gs400,

                borderRadius: BorderRadius.circular(
                  AppRadius.radiusfull,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Crea la representación visual de la onda de audio.
  // Las barras son decorativas por ahora.

  Widget _ondaAudio() {
    return SizedBox(
      height: AppSpacing.spacing900,

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,

        children: List.generate(45, (index) {

          // Generamos alturas distintas para simular
          // una forma de onda como la de tu imagen.
          final altura =
              AppSpacing.spacingy200 +
              ((index * 7 + index * index) % 25)
                  .toDouble();

          final color = index < 22
              ? AppColors.primary500
              : AppColors.primary200;

          return Expanded(
            child: Container(
              height: altura,

              margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.spacing50 / 2,
              ),

              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(
                  AppRadius.radiusfull,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // Devuelve el color de la etiqueta según
  // la categoría de cada publicación.

  Color _colorCategoria(String categoria) {
    switch (categoria) {
      case 'Estudio':
        return AppFeedbackColors.success;

      case 'Trabajo':
        return AppColors.primary500;

      case 'Ideas':
        return AppFeedbackColors.warning;

      default:
        return AppColors.gs400;
    }
  }

  // Genera una tarjeta reutilizable.
  // Es parecida a _tarjetaGrabacion() de main.dart.

  Widget _tarjetaComunidad(
    PublicacionComunidad publicacion,
  ) {
    final favorito =
        _favoritos.contains(publicacion.titulo);

    final cantidadFavoritos =
        publicacion.favoritos + (favorito ? 1 : 0);

    return Container(
      margin: const EdgeInsets.only(
        bottom: AppGap.gapcomponent,
      ),

      padding: const EdgeInsets.all(
        AppPadding.paddingmd,
      ),

      decoration: BoxDecoration(
        color: AppColors.gs50,

        borderRadius: BorderRadius.circular(
          AppRadius.radiusm,
        ),

        border: Border.all(
          color: AppColors.gs300,
        ),

        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          // Parte superior: botón play, título,
          // nombre del autor y duración.

          Row(
            children: [
              InkWell(
                onTap: () {
                  _mensaje(
                    'La reproducción de Comunidad '
                    'se conectará a los audios publicados.',
                  );
                },

                child: const CircleAvatar(
                  radius: AppRadius.radiusl,
                  backgroundColor: AppColors.primary50,

                  child: Icon(
                    Icons.play_arrow,
                    color: AppColors.primary500,
                    size: 30,
                  ),
                ),
              ),

              const SizedBox(
                width: AppGap.gapcomponent,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    Text(
                      publicacion.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,

                      style: AppTypography.s1.copyWith(
                        color: AppColors.gs900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(
                      height: AppGap.gaptight,
                    ),

                    Row(
                      children: [
                        CircleAvatar(
                          radius: AppSpacing.spacingy200,
                          backgroundColor:
                              AppColors.primary100,

                          child: Text(
                            publicacion.autor.substring(0, 1),

                            style: AppTypography.cptn.copyWith(
                              color: AppColors.gs900,
                            ),
                          ),
                        ),

                        const SizedBox(
                          width: AppGap.gaprelated,
                        ),

                        Expanded(
                          child: Text(
                            publicacion.autor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,

                            style: AppTypography.cptn.copyWith(
                              color: AppColors.gs700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Text(
                publicacion.duracion,

                style: AppTypography.cptn.copyWith(
                  color: AppColors.gs600,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: AppGap.gapcomponent,
          ),

          // Onda de audio azul.
          Padding(
            padding: const EdgeInsets.only(
              left: AppPadding.paddinglg,
            ),
            child: _ondaAudio(),
          ),

          const SizedBox(
            height: AppGap.gaprelated,
          ),

          // Parte inferior: comentarios, favoritos,
          // categoría y menú de tres puntos.

          Row(
            children: [
              InkWell(
                onTap: () {
                  _mensaje(
                    'Los comentarios se conectarán '
                    'a Firebase más adelante.',
                  );
                },

                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.gs700,
                      size: 20,
                    ),

                    const SizedBox(
                      width: AppGap.gaptight,
                    ),

                    Text(
                      '${publicacion.comentarios}',
                      style: AppTypography.cptn.copyWith(
                        color: AppColors.gs700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: AppGap.gapgroup,
              ),

              InkWell(
                onTap: () {
                  setState(() {
                    if (favorito) {
                      _favoritos.remove(
                        publicacion.titulo,
                      );
                    } else {
                      _favoritos.add(
                        publicacion.titulo,
                      );
                    }
                  });
                },

                child: Row(
                  children: [
                    Icon(
                      favorito
                          ? Icons.favorite
                          : Icons.favorite_border,

                      color: favorito
                          ? AppColors.primary500
                          : AppColors.gs700,

                      size: 20,
                    ),

                    const SizedBox(
                      width: AppGap.gaptight,
                    ),

                    Text(
                      '$cantidadFavoritos',
                      style: AppTypography.cptn.copyWith(
                        color: AppColors.gs700,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Etiqueta de categoría con color suave.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppPadding.paddingsm,
                  vertical: AppPadding.paddingxs,
                ),

                decoration: BoxDecoration(
                  color: _colorCategoria(
                    publicacion.categoria,
                  ).withValues(alpha: 0.15),

                  borderRadius: BorderRadius.circular(
                    AppRadius.radiuss,
                  ),
                ),

                child: Text(
                  publicacion.categoria,

                  style: AppTypography.cptn.copyWith(
                    color: AppColors.gs900,
                  ),
                ),
              ),

              PopupMenuButton<String>(
                color: AppColors.gs300,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppRadius.radiusm,
                  ),
                ),

                icon: const Icon(
                  Icons.more_vert,
                  color: AppColors.gs700,
                ),

                onSelected: (valor) {
                  if (valor == 'guardar') {
                    _mensaje(
                      'Esta función se conectará '
                      'a tus grabaciones guardadas.',
                    );
                  }
                },

                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'guardar',
                    child: Text('Guardar publicación'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // build construye toda la pantalla Comunidad.
  // No agregamos Scaffold ni barra inferior aquí,
  // porque esos ya existen en main.dart.

  @override
  Widget build(BuildContext context) {
    final publicaciones = _publicacionesFiltradas;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppPadding.paddinglg,
      ),

      children: [

        // Título principal.
        Text(
          'Comunidad',

          style: AppTypography.h5.copyWith(
            color: AppColors.gs900,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(
          height: AppGap.gapgroup,
        ),

        // Buscador de publicaciones.
        Container(
          decoration: BoxDecoration(
            color: AppColors.gs300,

            borderRadius: BorderRadius.circular(
              AppRadius.radiusm,
            ),
          ),

          child: TextField(
            style: AppTypography.b2.copyWith(
              color: AppColors.gs900,
            ),

            onChanged: (valor) {
              setState(() {
                _busqueda = valor.trim();
              });
            },

            decoration: InputDecoration(
              hintText: 'Buscar en la comunidad',

              hintStyle: AppTypography.b2.copyWith(
                color: AppColors.gs600,
              ),

              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.gs700,
              ),

              border: InputBorder.none,

              contentPadding: const EdgeInsets.all(
                AppPadding.paddingmd,
              ),
            ),
          ),
        ),

        const SizedBox(
          height: AppGap.gapgroup,
        ),

        // Categorías con la misma línea azul
        // que Todas y Favoritos de Mis Grabaciones.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,

          children: [
            for (final categoria in _categorias) ...[
              _pestanaComunidad(categoria),

              if (categoria != _categorias.last)
                const SizedBox(
                  width: AppGap.gaprelated,
                ),
            ],

            // Botón de filtro y orden.
            PopupMenuButton<String>(
              color: AppColors.gs300,

              icon: const Icon(
                Icons.filter_list,
                color: AppColors.gs900,
              ),

              tooltip: 'Ordenar publicaciones',

              onSelected: (valor) {
                setState(() {
                  _orden = valor;
                });
              },

              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'recientes',
                  child: Text('Orden original'),
                ),

                const PopupMenuItem(
                  value: 'favoritos',
                  child: Text('Más populares'),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(
          height: AppGap.gapgroup,
        ),

        // Si no hay resultados mostramos un mensaje.
        if (publicaciones.isEmpty)
          Padding(
            padding: const EdgeInsets.only(
              top: AppGap.gapsection,
            ),
            child: Center(
              child: Text(
                'No se encontraron publicaciones.',

                style: AppTypography.b2.copyWith(
                  color: AppColors.gs600,
                ),
              ),
            ),
          ),

        // Creamos una tarjeta por cada publicación.
        for (final publicacion in publicaciones)
          _tarjetaComunidad(publicacion),

        const SizedBox(
          height: AppGap.gapsection,
        ),
      ],
    );
  }
}
