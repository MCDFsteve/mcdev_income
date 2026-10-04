import 'package:path/path.dart' as p;

import '../ui/ore_material.dart';
import 'launcher_service.dart';
import 'project_icon_stub.dart'
    if (dart.library.io) 'project_icon_io.dart'
    as backend;

class ModProjectIcon extends StatelessWidget {
  const ModProjectIcon({super.key, required this.project, this.size = 40});

  final ModProject project;
  final double size;

  @override
  Widget build(BuildContext context) {
    final packs = [
      ...project.packs.where((pack) => pack.type != 'resources'),
      ...project.packs.where((pack) => pack.type == 'resources'),
    ];
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: backend.buildProjectIcon(
          paths: packs
              .map((pack) => p.join(pack.directory, 'pack_icon.png'))
              .toSet()
              .toList(),
          size: size,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
          fallback: Icon(
            Icons.extension,
            size: size * .8,
            color: OreTheme.of(context).colors.textMuted,
          ),
        ),
      ),
    );
  }
}
