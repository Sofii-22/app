import 'package:flutter/material.dart';
import 'theme/theme.dart';
import 'views/lists.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: audioMack,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      // app bar
      appBar: AppBar(
        title: const Text('Cards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),

      // contenido scrolleable
      body: ListView(
        padding: const EdgeInsets.all(
          AppSpacing.spacing16,
        ),
        children: [
          // card básica
          Text(
            'Card básica',
            style: text.headlineLarge,
          ),

          const SizedBox(
            height: AppSpacing.spacing16,
          ),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(
                AppSpacing.spacing16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Título de la card',
                    style: text.titleLarge,
                  ),

                  const SizedBox(
                    height: AppSpacing.spacing8,
                  ),

                  Text(
                    'Una card puede tener varias configuraciones.',
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: AppSpacing.spacing32,
          ),

          // card con icono
          Text(
            'Card con icono',
            style: text.headlineLarge,
          ),

          const SizedBox(
            height: AppSpacing.spacing16,
          ),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(
                AppSpacing.spacing16,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(
                      Icons.music_note,
                      color: colors.onPrimaryContainer,
                    ),
                  ),

                  const SizedBox(
                    width: AppSpacing.spacing16,
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Música',
                          style: text.titleLarge,
                        ),

                        Text(
                          'Dos líneas, contenido secundario',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: AppSpacing.spacing32,
          ),

          // card con imagen
          Text(
            'Card con imagen',
            style: text.headlineLarge,
          ),

          const SizedBox(
            height: AppSpacing.spacing16,
          ),

          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // imagen
                SizedBox(
                  width: double.infinity,
                  height: 180,
                  child: Image.asset(
                    'assets/images/kaleko.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(
                    AppSpacing.spacing16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kaleko Urdangak',
                        style: text.titleLarge,
                      ),

                      const SizedBox(
                        height: AppSpacing.spacing8,
                      ),

                      Text(
                        '1200',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: AppSpacing.spacing32,
          ),

          // card horizontal
          Text(
            'Card horizontal',
            style: text.headlineLarge,
          ),

          const SizedBox(
            height: AppSpacing.spacing16,
          ),

          Card(
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // thumbnail
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Image.asset(
                    'assets/images/kaleko.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(
                      AppSpacing.spacing16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kaleko Urdangak',
                          style: text.titleLarge,
                        ),

                        const SizedBox(
                          height: AppSpacing.spacing8,
                        ),

                        Text(
                          'Card horizontal con miniatura y contenido',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: AppSpacing.spacing32,
          ),

          // card con acciones
          Text(
            'Card con acciones',
            style: text.headlineLarge,
          ),

          const SizedBox(
            height: AppSpacing.spacing16,
          ),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(
                AppSpacing.spacing16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nueva Canción',
                    style: text.titleLarge,
                  ),

                  const SizedBox(
                    height: AppSpacing.spacing8,
                  ),

                  Text(
                    'Botones en una card',
                    style: text.bodyMedium,
                  ),

                  const SizedBox(
                    height: AppSpacing.spacing16,
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {},
                        child: const Text('Cancelar'),
                      ),

                      FilledButton(
                        onPressed: () {},
                        child: const Text('Ver más'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: AppSpacing.spacing32,
          ),

          // card tipo red social
          Text(
            'Card tipo redes sociales',
            style: text.headlineLarge,
          ),

          const SizedBox(
            height: AppSpacing.spacing16,
          ),

          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // heading
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.primary,
                    child: Icon(
                      Icons.person,
                      color: colors.onPrimary,
                    ),
                  ),

                  title: const Text(
                    'Kaleko Urdangak',
                  ),

                  subtitle: const Text(
                    'Euskal Herria',
                  ),

                  trailing: IconButton(
                    icon: const Icon(
                      Icons.more_vert,
                    ),
                    onPressed: () {},
                  ),
                ),

                // imagen
                SizedBox(
                  width: double.infinity,
                  height: 320,
                  child: Image.asset(
                    'assets/images/kaleko.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),

                // acciones
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.favorite_border,
                      ),
                      onPressed: () {},
                    ),

                    IconButton(
                      icon: const Icon(
                        Icons.chat_bubble_outline,
                      ),
                      onPressed: () {},
                    ),

                    IconButton(
                      icon: const Icon(
                        Icons.send_outlined,
                      ),
                      onPressed: () {},
                    ),

                    const Spacer(),

                    IconButton(
                      icon: const Icon(
                        Icons.bookmark_border,
                      ),
                      onPressed: () {},
                    ),
                  ],
                ),

                // descripción
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.spacing16,
                    0,
                    AppSpacing.spacing16,
                    AppSpacing.spacing16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1.234 Me gusta',
                        style: text.labelLarge,
                      ),

                      const SizedBox(
                        height: AppSpacing.spacing8,
                      ),

                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Kaleko Urdangak ',
                              style: text.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            TextSpan(
                              text: 'Nueva publicación.',
                              style: text.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: AppSpacing.spacing32,
          ),

          // segunda card tipo red social
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // heading
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.secondaryContainer,
                    child: const Text('K'),
                  ),

                  title: const Text(
                    'Kaleko Urdangak',
                  ),

                  subtitle: const Text(
                    'Hace 2 horas',
                  ),

                  trailing: IconButton(
                    icon: const Icon(
                      Icons.more_vert,
                    ),
                    onPressed: () {},
                  ),
                ),

                // imagen
                SizedBox(
                  width: double.infinity,
                  height: 240,
                  child: Image.asset(
                    'assets/images/kaleko.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),

                // descripción
                Padding(
                  padding: const EdgeInsets.all(
                    AppSpacing.spacing16,
                  ),
                  child: Text(
                    'Puede ser también sin tanto texto.',
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: AppSpacing.spacing32,
          ),
        ],
      ),

      // bottom navigatio
  bottomNavigationBar: NavigationBar(
  selectedIndex: _selectedIndex,
  onDestinationSelected: (index) {
    setState(() {
      _selectedIndex = index;
    });

    // navegación a listas
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ListsView(),
        ),
      );
    }
  },
        
        destinations: const [
          // comunidad
          NavigationDestination(
            icon: Icon(
              Icons.groups_outlined,
            ),
            selectedIcon: Icon(
              Icons.groups,
            ),
            label: 'Comunidad',
          ),

          // buscar
          NavigationDestination(
            icon: Icon(
              Icons.search_outlined,
            ),
            selectedIcon: Icon(
              Icons.search,
            ),
            label: 'Buscar',
          ),

          // listas
          NavigationDestination(
            icon: Icon(
              Icons.format_list_bulleted_outlined,
            ),
            selectedIcon: Icon(
              Icons.format_list_bulleted,
            ),
            label: 'Listas',
          ),
        ],
      ),
    );
  }
}
