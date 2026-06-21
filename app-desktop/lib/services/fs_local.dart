// Acceso al sistema de archivos LOCAL de la PC.
//
// Usa imports condicionales: en escritorio/móvil (dart:io) accede al disco
// real; en web (sin dart:io) queda deshabilitado de forma elegante. Así la
// misma app compila para web y para nativo.
export 'fs_local_stub.dart' if (dart.library.io) 'fs_local_io.dart';
