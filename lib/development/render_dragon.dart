const dxmtArchiveUrl =
    'https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz';
const dxmtArchiveHash =
    '8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d';
const rendererPatchHash =
    '5b6d10af9d1914e889d107e3980013af7c1bfc0e584fb122fafa111292957f79';
const rendererInjectorHash =
    'de618afb0d517506f83decebb34dc2456e829ae6ef50ed97fe522127319fb48b';
const wineMetalBridgeHash =
    'cb1649390b73064804a87761eee743fe142d6056dc9678eb4c1ee804803ed6bd';
const dxmtFiles = {
  'x86_64-windows/d3d11.dll':
      '7ca382af0eb32d8a432f6efb14d594fefb45673663be1f7e6682254bff885c47',
  'x86_64-windows/dxgi.dll':
      'fc58aae0aba511a1ec4d2417e5bba6adb888bb14315d0f59cccdfd27f670d544',
  'x86_64-windows/winemetal.dll':
      '514245d533c750599614311a792c45ed600aef52948571d98c0fc70fd3df16e0',
  'x86_64-unix/winemetal.so':
      '3d50d7f39c64778c71d0af2fce1cde818d09ffbce7c4f7b8ae24ae1df567c0ca',
};

Map<String, String> renderDragonOptions(bool vibrant) => {
  'graphics_mode': vibrant ? '2' : '1',
  // Deferred depth/volume targets do not use the old OpenGL MSAA setting.
  'gfx_msaa': '1',
};

const renderDragonEnvironment = {
  'WINEDLLOVERRIDES': 'kerberos=;d3d11,dxgi,winemetal=b',
  'DXMT_LOG_LEVEL': 'warn',
};

String restoreRenderDragonOptions(String current, String original) {
  const keys = {'graphics_mode', 'gfx_msaa'};
  final values = <String, String>{};
  for (final line
      in original
          .replaceFirst(RegExp(r'^\uFEFF'), '')
          .split(RegExp(r'\r?\n'))) {
    final colon = line.indexOf(':');
    if (colon >= 0 && keys.contains(line.substring(0, colon))) {
      values[line.substring(0, colon)] = line;
    }
  }
  final newline = current.contains('\r\n') ? '\r\n' : '\n';
  final lines = current.split(RegExp(r'\r?\n')).where((line) {
    final colon = line.indexOf(':');
    return colon < 0 || !keys.contains(line.substring(0, colon));
  }).toList();
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  lines.addAll(values.values);
  return '${lines.join(newline)}$newline';
}
