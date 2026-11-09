import 'package:flutter/material.dart';



class AppColors{

//PRIMARY

static const primary50 = Color(0xFFE9ECFF);
static const primary100 = Color (0xFFC8CFFD);
static const primary200 = Color (0xFFA1B0FC);
static const primary300 = Color (0xFF7690FC);
static const primary400 = Color (0xFF5075FA);
static const primary500 = Color (0xFF1D5BF7); // BASE
static const primary600 = Color (0xFF1552EB);
static const primary700 = Color (0xFF0046DE);
static const primary800 = Color (0xFF003BD3);
static const primary900 = Color (0xFF0024C2);

// SECONDARY

static const secondary50 = Color(0xFFDDF6FD);
static const secondary100 = Color (0xFFADE2FA);
static const secondary200 = Color (0xFF71D7F9); // BASE
static const secondary300 = Color (0xFF1EC7F7);
static const secondary400 = Color (0xFF00BCF9);
static const secondary500 = Color (0xFF02AFF8);
static const secondary600 = Color (0xFF00A1E9);
static const secondary700 = Color (0xFF038DD7);
static const secondary800 = Color (0xFF027DC4);
static const secondary900 = Color (0xFF015CA3);

// GREY SCALE

static const gs50 = Color(0xFFFFFFFF);
static const gs100 = Color (0xFFFAFAFA);
static const gsy200 = Color (0xFFF5F5F5); // BASE
static const gs300 = Color (0xFFF0F0F0);
static const gs400 = Color (0xFFDEDEDE);
static const gs500 = Color (0xFFC2C2C2);
static const gs600 = Color (0xFF979797);
static const gs700 = Color (0xFF818181);
static const gs800 = Color (0xFF606060);
static const gs900 = Color (0xFF3C3C3C);


}


//METRICAS

class AppSpacing {

static const double spacing50 = 2;
static const double spacing100 = 4;
static const double spacingy200 = 8; 
static const double spacing300 = 12;
static const double spacing400 = 16;
static const double spacing500 = 20;
static const double spacing600 = 24;
static const double spacing700 = 32;
static const double spacing800 = 40;
static const double spacing900 = 48;


}

//RADIUS

class AppRadius{

static const double radiusnone = 0;
static const double radiusxs = 4;
static const double radiuss = 8; 
static const double radiusm = 16;
static const double radiusl = 24;
static const double radiusfull = 9999;


}

// PADDING

class AppPadding {

static const double paddingxs = 4;
static const double paddingsm = 8;
static const double paddingmd = 16;
static const double paddinglg = 24; 
static const double paddingxl = 40;

}

// MARGIN

class AppMargin {

static const double marginxs = 4;
static const double marginsm = 8;
static const double marginmd = 16;
static const double marginlg = 24;
static const double marginxl = 40;

}

// GAP

class AppGap { 

static const double gaptight = 4;
static const double gaprelated = 8;
static const double gapcomponent = 16;
static const double gapgroup = 24;
static const double gapsection = 40;

}

// TIPOGRAFIA

class AppTypography{

 static const String fontFamily = "DM Sans" ;

//HEADLINE 1

static const TextStyle h1 = TextStyle(
  fontSize: 101,
  fontWeight: FontWeight.w700,
  letterSpacing: -1.5,
);

//HEADLINE 2

static const TextStyle h2 = TextStyle(
  fontSize: 63,
  fontWeight: FontWeight.w300,
  letterSpacing: -0.5,
);

//HEADLINE 3

static const TextStyle h3 = TextStyle(
  fontSize: 50,
  fontWeight: FontWeight.w300,
  letterSpacing: 0,
);

//HEADLINE 4

static const TextStyle h4 = TextStyle(
  fontSize: 36,
  fontWeight: FontWeight.w300,
  letterSpacing: 0.25,
);

//HEADLINE 5

static const TextStyle h5 = TextStyle(
  fontSize: 25,
  fontWeight: FontWeight.w300,
  letterSpacing: 0,
);

//HEADLINE 6

static const TextStyle h6 = TextStyle(
  fontSize: 21,
  fontWeight: FontWeight.w300,
  letterSpacing: 0.15,
);

//SUBTITLE 1

static const TextStyle s1 = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w300,
  letterSpacing: 0.15,
);

//SUBTITLE 2

static const TextStyle s2 = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w300,
  letterSpacing: 0.1,
);

//BODY 1

static const TextStyle b1 = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w300,
  letterSpacing: 0.5,
);

//BODY 2

static const TextStyle b2 = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w300,
  letterSpacing: 0.25,
);

//BUTTON

static const TextStyle butt = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w300,
  letterSpacing: 1.25,
);

//CAPTION

static const TextStyle cptn = TextStyle(
  fontSize: 13,
  letterSpacing: 0.4,
);

//OVERLINE

static const TextStyle over = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w300,
  letterSpacing: 1.5,
);

}

class AppFeedbackColors {

  //ERROR

  static const Color error = Color (0xFFF82E26);
  static const Color onError = Color (0xFFFFFFFF);

 //WARNING

  static const Color warning = Color (0xFFFFC512);
  static const Color onWarning = Color (0xFFFFFFFF);


 //Success

  static const Color success = Color (0xFF25B645);
  static const Color onSuccess = Color (0xFFFFFFFF);


}

final ThemeData voz = ThemeData(

  useMaterial3: true,

  // familia tipográfica
  fontFamily: 'DM Sans',

  // escala tipográfica
  textTheme: const TextTheme(
   displayLarge: AppTypography.h1,
   displayMedium: AppTypography.h2,
   displaySmall: AppTypography.h3,

   headlineLarge: AppTypography.h4,
   headlineMedium: AppTypography.h5,
   headlineSmall: AppTypography.h6,

   titleLarge: AppTypography.s1,
   titleMedium: AppTypography.s2,
   bodyLarge: AppTypography.b1,
   bodyMedium: AppTypography.b2,

   labelLarge: AppTypography.butt,
   bodySmall: AppTypography.cptn,
   labelSmall: AppTypography.over,
    
  ),


);