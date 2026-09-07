import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      home: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color.fromRGBO(100, 12, 1, 1),

          leading: IconButton(
            icon: const Icon(Icons.menu),
            color: Colors.white,
            onPressed: () {},
          ),

          

          actions: [
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
                color: Colors.white,
              ),
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'perfil',
                  child: Row(
                    children: [
                      Icon(Icons.account_circle),
                      SizedBox(width: 10),
                      Text('Perfil'),
                    ],
                  ),
                ),

                const PopupMenuItem<String>(
                  value: 'configuracion',
                  child: Row(
                    children: [
                      Icon(Icons.settings),
                      SizedBox(width: 10),
                      Text('Configuración'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        body: ListView(
          children: [
            // CONTAINER 1
            Container(
              height: 200,
              width: double.infinity,
              color: const Color.fromARGB(255, 165, 28, 40),

              child: const Center(
                child: Text(
                  "Container 1",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // CONTAINER 2
            Container(
              height: 400,
              width: double.infinity,

              // Espacio FUERA del Container
              margin: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 10,
                bottom: 10,
              ),

              // Espacio DENTRO del Container
              padding: const EdgeInsets.all(40),

              color: const Color.fromARGB(255, 200, 10, 10),

              // Este Container amarillo permite ver el padding
              child: Container(
                color: Colors.yellow,

                child: const Text(
                  "Container 2",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                  ),
                ),
              ),
            ),
          ],
        ),

        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: const Color.fromRGBO(100, 12, 1, 1),

          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white,

          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.message),
              label: 'Mensajes',
            ),

            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'Buscar',
            ),

            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Inicio',
            ),
          ],
        ),
      ),
    );
  }
}