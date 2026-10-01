const performancePatchVersion = '3.8.0.313229';
const performanceGameHash =
    '01a64912e20bbe7568be446461262a4bb892f671a2a5e15d550db2017902e7aa';
const performancePatchAssets = {
  'graphics-patch.dll':
      '0e8cfbea1607db27a949a6bd5ff8c6107a6d2da8cff898d3516af0df50b351e9',
  'performance-inject.exe':
      '5a861693d8af5ee08ef481e1fe17cbec186899ece103435f714aca897ac24644',
};

bool supportsPerformancePatch(String? version) =>
    version == performancePatchVersion;
