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
            icon: const Icon(Icons.arrow_back),
            color: Colors.white,
            onPressed: () {},
          ),
          
           title: const Text(
            'DESCUBRIR LIBROS NUEVOS',
            style: TextStyle(
              color: Colors.white,
            ),
          ),

        

          actions: [
            IconButton(
            icon: const Icon(Icons.notifications),
            color: Colors.white,
            onPressed: () {},
          ),
          ],
        ),

        body: ListView(
          children: [

            // CONTAINER 1
            Container(
              height: 70,
              width: double.infinity,
              color: const Color.fromARGB(255, 165, 28, 40),

               margin: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: 16,
              ),

    
                ),
                 const SizedBox(height: 8),

            // CONTAINER 2
            Container(
              height: 160,
              width: double.infinity,

              // Espacio FUERA del Container
              margin: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 2,
              ),

               // Espacio DENTRO del Container
              padding: const EdgeInsets.only(
                left: 10.0,
                right: 400.0,
                top: 10.0,
                bottom: 10.0,
              ),

              color: const Color.fromARGB(255, 200, 10, 10),

              // Este Container gris permite ver el padding
              child: Container(
                color: Colors.grey,

                
              ),
            ),

            // CONTAINER 3
            Container(
              height: 160,
              width: double.infinity,

              // Espacio FUERA del Container
              margin: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 2,
                bottom: 2,
              ),

               // Espacio DENTRO del Container
              padding: const EdgeInsets.only(
                left: 10.0,
                right: 400.0,
                top: 10.0,
                bottom: 10.0,
              ),

              color: const Color.fromARGB(255, 200, 10, 10),

              // Este Container gris permite ver el padding
              child: Container(
                color: Colors.grey,

               
              ),
            ),

            // CONTAINER 4
            Container(
              height: 160,
              width: double.infinity,

              // Espacio FUERA del Container
              margin: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 2,
                bottom: 2,
              ),

              // Espacio DENTRO del Container
              padding: const EdgeInsets.only(
                left: 10.0,
                right: 400.0,
                top: 10.0,
                bottom: 10.0,
              ),

              color: const Color.fromARGB(255, 200, 10, 10),

              // Este Container gris permite ver el padding
              child: Container(
                color: Colors.grey,

                
              ),
            ),

            // CONTAINER 5
            Container(
              height: 160,
              width: double.infinity,

              // Espacio FUERA del Container
              margin: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 2,
                bottom: 2,
              ),

              // Espacio DENTRO del Container
              padding: const EdgeInsets.only(
                left: 10.0,
                right: 400.0,
                top: 10.0,
                bottom: 10.0,
              ),

              color: const Color.fromARGB(255, 200, 10, 10),

              // Este Container gris permite ver el padding
              child: Container(
                color: Colors.grey,

                
              ),
            ),

            // CONTAINER 6
            Container(
              height: 160,
              width: double.infinity,

              // Espacio FUERA del Container
              margin: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 2,
                bottom: 2,
              ),

               // Espacio DENTRO del Container
              padding: const EdgeInsets.only(
                left: 10.0,
                right: 400.0,
                top: 10.0,
                bottom: 10.0,
              ),

              color: const Color.fromARGB(255, 200, 10, 10),

              // Este Container gris permite ver el padding
              child: Container(
                color: Colors.grey,

               
              ),
            ),
             // CONTAINER 7
            Container(
              height: 160,
              width: double.infinity,

              // Espacio FUERA del Container
              margin: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 2,
                bottom: 2,
              ),

               // Espacio DENTRO del Container
              padding: const EdgeInsets.only(
                left: 10.0,
                right: 400.0,
                top: 10.0,
                bottom: 10.0,
              ),

              color: const Color.fromARGB(255, 200, 10, 10),

              // Este Container gris permite ver el padding
              child: Container(
                color: Colors.grey,

               
              ),
            ),

          ],

           ),
           
          bottomNavigationBar:BottomNavigationBar(
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
  
