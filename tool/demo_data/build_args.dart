// Arguments of the demo builder (tool/demo_data/build.dart). --config is
// required and has no default, so the builder can never write to a server by
// accident.

const demoDefaultDir = r'D:\0_CAPSTONE\verify\demo';

const demoBuildUsage = 'Usage: dart run tool/demo_data/build.dart --config <supabase_config.json> [--dir <folder>]\n'
    '  --config  the server to build on (required; e.g. D:\\0_CAPSTONE\\verify\\demo\\supabase_config.json)\n'
    '  --dir     where devices, SF1 files, state, accounts and the report go (default $demoDefaultDir)';

/// The parsed arguments, or null (print [demoBuildUsage]).
({String configPath, String dir})? parseBuildArgs(List<String> args) {
  String? config;
  var dir = demoDefaultDir;
  for (var i = 0; i < args.length; i++) {
    final value = i + 1 < args.length ? args[i + 1] : null;
    switch (args[i]) {
      case '--config' when value != null:
        config = value;
        i++;
      case '--dir' when value != null:
        dir = value;
        i++;
      default:
        return null;
    }
  }
  return config == null ? null : (configPath: config, dir: dir);
}
