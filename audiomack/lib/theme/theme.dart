import 'package:flutter/material.dart';

// metricas

class AppSpacing {
  static const double spacing4 = 4;
 ;
}

// corner radius

class AppRadius {
  static const double radius50 = 0;
 
}

// tipografía

class AppTypography {

  // headline

  static const TextStyle headline1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w500,
  );

}

// definición de colores

class AppColors {

  // primary

  static const primary50 = Color(0xFFF2EFFF);
 
}

// elevaciones

class AppElevation {
  static const double elevation0 = 0;




// tema audiomack

final ThemeData audioMack = ThemeData(

  useMaterial3: true,

  // familia tipográfica
  fontFamily: 'Montserrat',

  // escala tipográfica
  textTheme: const TextTheme(
    headlineLarge: AppTypography.headline1,
    
  ),

  // colores
  colorScheme: const ColorScheme.dark(

    // primary

    primary: AppColors.primary500,
    onPrimary: AppColors.neutral0,

    primaryContainer: AppColors.primary800,
    onPrimaryContainer: AppColors.primary50,

    primaryFixed: AppColors.primary500,
    primaryFixedDim: AppColors.primary600,

    onPrimaryFixed: AppColors.neutral0,
    onPrimaryFixedVariant: AppColors.primary50,

  ),

  // bottom navigation

navigationBarTheme: NavigationBarThemeData(
  height: 72,

  backgroundColor: AppColors.neutral900,

  indicatorColor: AppColors.primary500,

  iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
    (states) {
      if (states.contains(WidgetState.selected)) {
        return const IconThemeData(
          color: AppColors.neutral0,
        );
      }

      return const IconThemeData(
        color: AppColors.neutral400,
      );
    },
  ),

  labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
    (states) {
      if (states.contains(WidgetState.selected)) {
        return AppTypography.label2.copyWith(
          color: AppColors.neutral0,
        );
      }

      return AppTypography.label2.copyWith(
        color: AppColors.neutral400,
      );
    },
  ),
),

  // cards
  cardTheme: const CardThemeData(
    elevation: AppElevation.elevation2,
  ),
);
