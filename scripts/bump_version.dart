import 'dart:io';

void main(List<String> arguments) {
  final pubspecFile = File('pubspec.yaml');
  
  if (!pubspecFile.existsSync()) {
    print('Error: pubspec.yaml not found');
    exit(1);
  }
  
  final content = pubspecFile.readAsStringSync();
  final lines = content.split('\n');
  
  String? versionType = arguments.isNotEmpty ? arguments[0] : 'build';
  
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('version:')) {
      final versionLine = lines[i];
      final versionMatch = RegExp(r'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)').firstMatch(versionLine);
      
      if (versionMatch != null) {
        int major = int.parse(versionMatch.group(1)!);
        int minor = int.parse(versionMatch.group(2)!);
        int patch = int.parse(versionMatch.group(3)!);
        int build = int.parse(versionMatch.group(4)!);
        
        switch (versionType) {
          case 'major':
            major++;
            minor = 0;
            patch = 0;
            build++;
            break;
          case 'minor':
            minor++;
            patch = 0;
            build++;
            break;
          case 'patch':
            patch++;
            build++;
            break;
          case 'build':
          default:
            build++;
            break;
        }
        
        final newVersion = '$major.$minor.$patch+$build';
        lines[i] = 'version: $newVersion';
        
        print('Version bumped from ${versionMatch.group(0)?.substring(8)} to $newVersion');
        break;
      } else {
        print('Error: Could not parse version format');
        exit(1);
      }
    }
  }
  
  pubspecFile.writeAsStringSync(lines.join('\n'));
  print('pubspec.yaml updated successfully');
} 