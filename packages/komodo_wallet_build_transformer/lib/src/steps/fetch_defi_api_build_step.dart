import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:komodo_wallet_build_transformer/src/build_step.dart';
import 'package:path/path.dart' as path;

class FetchDefiApiStep extends BuildStep {
  factory FetchDefiApiStep.withBuildConfig(Map<String, dynamic> buildConfig) {
    final apiConfig = buildConfig['api'] as Map<String, dynamic>;
    return FetchDefiApiStep(
      projectRoot: Directory.current.path,
      apiCommitHash: apiConfig['api_commit_hash'],
      platformsConfig: apiConfig['platforms'],
      sourceUrls: List<String>.from(apiConfig['source_urls']),
      apiBranch: apiConfig['branch'],
      enabled: apiConfig['fetch_at_build_enabled'],
    );
  }

  FetchDefiApiStep({
    required this.projectRoot,
    required this.apiCommitHash,
    required this.platformsConfig,
    required this.sourceUrls,
    required this.apiBranch,
    this.selectedPlatform,
    this.forceUpdate = false,
    this.enabled = true,
  });

  @override
  final String id = idStatic;

  static const idStatic = 'fetch_defi_api';

  final String projectRoot;
  final String apiCommitHash;
  final Map<String, dynamic> platformsConfig;
  final List<String> sourceUrls;
  final String apiBranch;
  String? selectedPlatform;
  bool forceUpdate;
  bool enabled;

  @override
  Future<void> build() async {
    if (!enabled) {
      _logMessage('API update is not enabled in the configuration.');
      return;
    }
    try {
      await updateAPI();
    } catch (e) {
      stderr.writeln('Error updating API: $e');
      rethrow;
    }
  }

  @override
  Future<bool> canSkip() => Future.value(!enabled);

  @override
  Future<void> revert([Exception? e]) async {
    _logMessage('Reverting changes made by UpdateAPIStep...');
  }

  Future<void> updateAPI() async {
    if (!enabled) {
      _logMessage('API update is not enabled in the configuration.');
      return;
    }

    final platformsToUpdate = selectedPlatform != null &&
            platformsConfig.containsKey(selectedPlatform)
        ? [selectedPlatform!]
        : platformsConfig.keys.toList();

    for (final platform in platformsToUpdate) {
      final progressString =
          '${(platformsToUpdate.indexOf(platform) + 1)}/${platformsToUpdate.length}';
      stdout.writeln('=====================');
      stdout.writeln('[$progressString] Updating $platform platform...');
      await _updatePlatform(platform, platformsConfig);
      stdout.writeln('=====================');
    }
    _updateDocumentation();
  }

  static const String _overrideEnvName = 'OVERRIDE_DEFI_API_DOWNLOAD';

  /// If set, the OVERRIDE_DEFI_API_DOWNLOAD environment variable will override
  /// any default behavior/configuration. e.g.
  /// `flutter build web --release --dart-define=OVERRIDE_DEFI_API_DOWNLOAD=true`
  ///  or `OVERRIDE_DEFI_API_DOWNLOAD=true && flutter build web --release`
  ///
  /// If set to true/TRUE/True, the API will be fetched and downloaded on every
  /// build, even if it is already up-to-date with the configuration.
  ///
  /// If set to false/FALSE/False, the API fetching will be skipped, even if
  /// the existing API is not up-to-date with the coniguration.
  ///
  /// If unset, the default behavior will be used.
  ///
  /// If both the system environment variable and the dart-defined environment
  /// variable are set, the dart-defined variable will take precedence.
  ///
  /// NB! Setting the value to false is not the same as it being unset.
  /// If the value is unset, the default behavior will be used.
  /// Bear this in mind when setting the value as a system environment variable.
  ///
  /// See `BUILD_CONFIG_README.md`  in `app_build/BUILD_CONFIG_README.md`.
  bool? get overrideDefiApiDownload =>
      const bool.hasEnvironment(_overrideEnvName)
          ? const bool.fromEnvironment(_overrideEnvName)
          : Platform.environment[_overrideEnvName] != null
              ? bool.tryParse(Platform.environment[_overrideEnvName]!,
                  caseSensitive: false)
              : null;

  Future<void> _updatePlatform(
      String platform, Map<String, dynamic> config) async {
    final updateMessage = overrideDefiApiDownload != null
        ? '${overrideDefiApiDownload! ? 'FORCING' : 'SKIPPING'} update of $platform platform because OVERRIDE_DEFI_API_DOWNLOAD is set to $overrideDefiApiDownload'
        : null;

    if (updateMessage != null) {
      stdout.writeln(updateMessage);
    }

    final destinationFolder = _getPlatformDestinationFolder(platform);
    final isOutdated =
        await _checkIfOutdated(platform, destinationFolder, config);

    if (!_shouldUpdate(isOutdated)) {
      _logMessage('$platform platform is up to date.');
      await _postUpdateActions(platform, destinationFolder);
      return;
    }

    String? zipFilePath;
    for (final sourceUrl in sourceUrls) {
      try {
        final zipFileUrl = await _findZipFileUrl(platform, config, sourceUrl);
        zipFilePath = await _downloadFile(zipFileUrl, destinationFolder);

        if (await _verifyChecksum(zipFilePath, platform)) {
          await _extractZipFile(zipFilePath, destinationFolder);
          _updateLastUpdatedFile(platform, destinationFolder, zipFilePath);
          _logMessage('$platform platform update completed.');
          break; // Exit loop if update is successful
        } else {
          stdout
              .writeln('SHA256 Checksum verification failed for $zipFilePath');
          if (sourceUrl == sourceUrls.last) {
            throw Exception(
              'API fetch failed for all source URLs: $sourceUrls',
            );
          }
        }
      } catch (e) {
        stdout.writeln('Error updating from source $sourceUrl: $e');
        if (sourceUrl == sourceUrls.last) {
          rethrow;
        }
      } finally {
        if (zipFilePath != null) {
          try {
            File(zipFilePath).deleteSync();
            _logMessage('Deleted zip file $zipFilePath');
          } catch (e) {
            _logMessage('Error deleting zip file: $e', error: true);
          }
        }
      }
    }

    await _postUpdateActions(platform, destinationFolder);
  }

  bool _shouldUpdate(bool isOutdated) {
    return overrideDefiApiDownload == true ||
        (overrideDefiApiDownload != false && (forceUpdate || isOutdated));
  }

  Future<String> _downloadFile(String url, String destinationFolder) async {
    _logMessage('Downloading $url...');
    final response = await http.get(Uri.parse(url));
    _checkResponseSuccess(response);

    final zipFileName = path.basename(url);
    final zipFilePath = path.join(destinationFolder, zipFileName);

    final directory = Directory(destinationFolder);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final zipFile = File(zipFilePath);
    try {
      await zipFile.writeAsBytes(response.bodyBytes);
    } catch (e) {
      _logMessage('Error writing file: $e', error: true);
      rethrow;
    }

    _logMessage('Downloaded $zipFileName');
    return zipFilePath;
  }

  Future<bool> _verifyChecksum(String filePath, String platform) async {
    final validChecksums = List<String>.from(
      platformsConfig[platform]['valid_zip_sha256_checksums'],
    );

    _logMessage('validChecksums: $validChecksums');

    final fileBytes = await File(filePath).readAsBytes();
    final fileSha256Checksum = sha256.convert(fileBytes).toString();

    if (validChecksums.contains(fileSha256Checksum)) {
      stdout.writeln('Checksum validated for $filePath');
      return true;
    } else {
      stderr.writeln(
        'SHA256 Checksum mismatch for $filePath: expected any of '
        '$validChecksums, got $fileSha256Checksum',
      );
      return false;
    }
  }

  void _updateLastUpdatedFile(
      String platform, String destinationFolder, String zipFilePath) {
    final lastUpdatedFile =
        File(path.join(destinationFolder, '.api_last_updated_$platform'));
    final currentTimestamp = DateTime.now().toIso8601String();
    final fileChecksum =
        sha256.convert(File(zipFilePath).readAsBytesSync()).toString();
    lastUpdatedFile.writeAsStringSync(json.encode({
      'api_commit_hash': apiCommitHash,
      'timestamp': currentTimestamp,
      'checksums': [fileChecksum]
    }));
    stdout.writeln('Updated last updated file for $platform.');
  }

  Future<bool> _checkIfOutdated(String platform, String destinationFolder,
      Map<String, dynamic> config) async {
    final lastUpdatedFilePath =
        path.join(destinationFolder, '.api_last_updated_$platform');
    final lastUpdatedFile = File(lastUpdatedFilePath);

    if (!lastUpdatedFile.existsSync()) {
      return true;
    }

    try {
      final lastUpdatedData = json.decode(lastUpdatedFile.readAsStringSync());
      if (lastUpdatedData['api_commit_hash'] == apiCommitHash) {
        final storedChecksums =
            List<String>.from(lastUpdatedData['checksums'] ?? []);
        final targetChecksums =
            List<String>.from(config[platform]['valid_zip_sha256_checksums']);

        if (storedChecksums.toSet().containsAll(targetChecksums)) {
          _logMessage("version: $apiCommitHash and SHA256 checksum match.");
          return false;
        }
      }
    } catch (e) {
      _logMessage(
        'Error reading or parsing .api_last_updated_$platform: $e',
        error: true,
      );
      lastUpdatedFile.deleteSync();
      rethrow;
    }

    return true;
  }

  Future<void> _updateWebPackages() async {
    _logMessage('Updating Web platform...');
    String npmPath = 'npm';
    if (Platform.isWindows) {
      npmPath = path.join('C:', 'Program Files', 'nodejs', 'npm.cmd');
      _logMessage('Using npm path: $npmPath');
    }
    final installResult =
        await Process.run(npmPath, ['install'], workingDirectory: projectRoot);
    if (installResult.exitCode != 0) {
      throw Exception('npm install failed: ${installResult.stderr}');
    }

    final buildResult = await Process.run(npmPath, ['run', 'build'],
        workingDirectory: projectRoot);
    if (buildResult.exitCode != 0) {
      throw Exception('npm run build failed: ${buildResult.stderr}');
    }

    _logMessage('Web platform updated successfully.');
  }

  Future<void> _updateLinuxPlatform(String destinationFolder) async {
    _logMessage('Updating Linux platform...');
    // Update the file permissions to make it executable. As part of the
    // transition from mm2 naming to kdfi, update whichever file is present.
    // ignore: unused_local_variable
    final binaryNames = ['mm2', 'kdfi']
        .map((e) => path.join(destinationFolder, e))
        .where((filePath) => File(filePath).existsSync());
    if (!Platform.isWindows) {
      for (var filePath in binaryNames) {
        Process.run('chmod', ['+x', filePath]);
      }
    }

    _logMessage('Linux platform updated successfully.');
  }

  String _getPlatformDestinationFolder(String platform) {
    if (platformsConfig.containsKey(platform)) {
      return path.join(projectRoot, platformsConfig[platform]['path']);
    } else {
      throw ArgumentError('Invalid platform: $platform');
    }
  }

  Future<String> _findZipFileUrl(
      String platform, Map<String, dynamic> config, String sourceUrl) async {
    if (sourceUrl.startsWith('https://api.github.com/repos/')) {
      return await _fetchFromGitHub(platform, config, sourceUrl);
    } else {
      return await _fetchFromBaseUrl(platform, config, sourceUrl);
    }
  }

  Future<String> _fetchFromGitHub(
      String platform, Map<String, dynamic> config, String sourceUrl) async {
    final repoMatch = RegExp(r'^https://api\.github\.com/repos/([^/]+)/([^/]+)')
        .firstMatch(sourceUrl);
    if (repoMatch == null) {
      throw ArgumentError('Invalid GitHub repository URL: $sourceUrl');
    }

    final owner = repoMatch.group(1)!;
    final repo = repoMatch.group(2)!;
    final releasesUrl = 'https://api.github.com/repos/$owner/$repo/releases';
    final response = await http.get(Uri.parse(releasesUrl));
    _checkResponseSuccess(response);

    final releases = json.decode(response.body) as List<dynamic>;
    final apiVersionShortHash = apiCommitHash.substring(0, 7);
    final matchingKeyword = config[platform]['matching_keyword'];

    for (final release in releases) {
      final assets = release['assets'] as List<dynamic>;
      for (final asset in assets) {
        final url = asset['browser_download_url'] as String;

        if (url.contains(matchingKeyword) &&
            url.contains(apiVersionShortHash)) {
          final commitHash =
              await _getCommitHashForRelease(release['tag_name'], owner, repo);
          if (commitHash == apiCommitHash) {
            return url;
          }
        }
      }
    }

    throw Exception(
        'Zip file not found for platform $platform in GitHub releases');
  }

  Future<String> _getCommitHashForRelease(
      String tag, String owner, String repo) async {
    final commitsUrl = 'https://api.github.com/repos/$owner/$repo/commits/$tag';
    final response = await http.get(Uri.parse(commitsUrl));
    _checkResponseSuccess(response);

    final commit = json.decode(response.body);
    return commit['sha'];
  }

  Future<String> _fetchFromBaseUrl(
      String platform, Map<String, dynamic> config, String sourceUrl) async {
    final url = '$sourceUrl/$apiBranch/';
    final response = await http.get(Uri.parse(url));
    _checkResponseSuccess(response);

    final document = parser.parse(response.body);
    final matchingKeyword = config[platform]['matching_keyword'];
    final extensions = ['.zip'];
    final apiVersionShortHash = apiCommitHash.substring(0, 7);

    for (final element in document.querySelectorAll('a')) {
      final href = element.attributes['href'];
      if (href != null &&
          href.contains(matchingKeyword) &&
          extensions.any((extension) => href.endsWith(extension)) &&
          href.contains(apiVersionShortHash)) {
        return '$sourceUrl/$apiBranch/$href';
      }
    }

    throw Exception('Zip file not found for platform $platform');
  }

  void _checkResponseSuccess(http.Response response) {
    if (response.statusCode != 200) {
      throw HttpException(
          'Failed to fetch data: ${response.statusCode} ${response.reasonPhrase}');
    }
  }

  Future<void> _postUpdateActions(String platform, String destinationFolder) {
    if (platform == 'web') {
      return _updateWebPackages();
    } else if (platform == 'linux') {
      return _updateLinuxPlatform(destinationFolder);
    }
    return Future.value();
  }

  Future<void> _extractZipFile(
      String zipFilePath, String destinationFolder) async {
    try {
      // Determine the platform to use the appropriate extraction command
      if (Platform.isMacOS || Platform.isLinux) {
        // For macOS and Linux, use the `unzip` command
        final result =
            await Process.run('unzip', [zipFilePath, '-d', destinationFolder]);
        if (result.exitCode != 0) {
          throw Exception('Error extracting zip file: ${result.stderr}');
        }
      } else if (Platform.isWindows) {
        // For Windows, use PowerShell's Expand-Archive command
        final result = await Process.run('powershell', [
          'Expand-Archive',
          '-Path',
          zipFilePath,
          '-DestinationPath',
          destinationFolder
        ]);
        if (result.exitCode != 0) {
          throw Exception('Error extracting zip file: ${result.stderr}');
        }
      } else {
        _logMessage(
          'Unsupported platform: ${Platform.operatingSystem}',
          error: true,
        );
        throw UnsupportedError('Unsupported platform');
      }
      _logMessage('Extraction completed.');
    } catch (e) {
      _logMessage('Failed to extract zip file: $e');
    }
  }

  void _updateDocumentation() {
    final documentationFile = File('$projectRoot/docs/UPDATE_API_MODULE.md');
    final content = documentationFile.readAsStringSync().replaceAllMapped(
          RegExp(r'(Current api module version is) `([^`]+)`'),
          (match) => '${match[1]} `$apiCommitHash`',
        );
    documentationFile.writeAsStringSync(content);
    _logMessage('Updated API version in documentation.');
  }
}

late final ArgResults _argResults;

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('platform', abbr: 'p', help: 'Specify the platform to update')
    ..addOption('api-version',
        abbr: 'a', help: 'Specify the API version to update to')
    ..addFlag('force',
        abbr: 'f', negatable: false, help: 'Force update the API module')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Display usage information');

  _argResults = parser.parse(arguments);

  if (_argResults['help']) {
    _logMessage('Usage: dart app_build/build_steps.dart [options]');
    _logMessage(parser.usage);
    return;
  }

  final projectRoot = Directory.current.path;
  final configFile = File('$projectRoot/app_build/build_config.json');
  final config = json.decode(configFile.readAsStringSync());

  final platform = _argResults.option('platform');
  final apiVersion =
      _argResults.option('api-version') ?? config['api']['api_commit_hash'];
  final forceUpdate = _argResults.flag('force');

  final fetchDefiApiStep = FetchDefiApiStep(
    projectRoot: projectRoot,
    apiCommitHash: apiVersion,
    platformsConfig: config['api']['platforms'],
    sourceUrls: List<String>.from(config['api']['source_urls']),
    apiBranch: config['api']['branch'],
    selectedPlatform: platform,
    forceUpdate: forceUpdate,
    enabled: true,
  );

  await fetchDefiApiStep.build();

  if (_argResults.wasParsed('api-version')) {
    config['api']['api_commit_hash'] = apiVersion;
    configFile.writeAsStringSync(json.encode(config));
  }
}

void _logMessage(String message, {bool error = false}) {
  final prefix = error ? 'ERROR' : 'INFO';
  final output = '[$prefix]: $message';
  if (error) {
    stderr.writeln(output);
  } else {
    stdout.writeln(output);
  }
}
