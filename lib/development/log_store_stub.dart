import 'development_logs.dart';
import 'development_storage.dart';

DevelopmentLogStore openDevelopmentLogs(String directory) => _UnsupportedLogs();

class _UnsupportedLogs extends DevelopmentLogStore {
  @override
  Future<List<DevelopmentLogFile>> list() async => [];
  @override
  Future<DevelopmentLogChunk> read(String path, {int? offset}) async =>
      throw const DevelopmentStorageException('此平台不支持本机游戏日志。');
  @override
  Future<void> exportOriginal(String source, String destination) async =>
      throw const DevelopmentStorageException('此平台不支持导出本机游戏日志。');
  @override
  Future<void> exportText(
    String source,
    String destination,
    String text,
  ) async => throw const DevelopmentStorageException('此平台不支持导出本机游戏日志。');
}
