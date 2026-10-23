class PlaybookOption {
  final String name;
  final String displayName;
  final String? description;
  final bool isChecked;
  final bool isRequired;
  final String type; // 'radio', 'checkbox', 'browser'

  const PlaybookOption({
    required this.name,
    required this.displayName,
    this.description,
    this.isChecked = false,
    this.isRequired = false,
    this.type = 'checkbox',
  });
}

class PlaybookConfig {
  final String title;
  final String version;
  final List<PlaybookOption> options;

  const PlaybookConfig({
    required this.title,
    required this.version,
    required this.options,
  });
}

class Playbook {
  final String name;
  final String description;
  final String downloadUrl;
  final bool requiresPassword;
  final String password;
  final bool isZipArchive; // true if .zip, false if .apbx

  const Playbook({
    required this.name,
    required this.description,
    required this.downloadUrl,
    this.requiresPassword = true,
    this.password = 'malte',
    this.isZipArchive = false,
  });

  static const List<Playbook> availablePlaybooks = [
    Playbook(
      name: 'AME 10 Beta',
      description: 'Ameliorated Windows 10 - Enhanced privacy and control',
      downloadUrl: 'https://download.amelabs.net/AME%2010%20Beta.apbx',
    ),
    Playbook(
      name: 'Privacy+',
      description: 'Ameliorated Privacy+ - Maximum privacy configuration',
      downloadUrl: 'https://download.amelabs.net/Privacy%2B.apbx',
    ),
    Playbook(
      name: 'ReviOS 25.10',
      description: 'Revision Playbook - Optimized Windows experience',
      downloadUrl:
          'https://github.com/meetrevision/playbook/releases/download/25.10/Revi-PB-25.10.apbx',
    ),
    Playbook(
      name: 'AtlasOS v0.5.0',
      description: 'Atlas Playbook - Performance-focused Windows configuration',
      downloadUrl:
          'https://github.com/Atlas-OS/Atlas/releases/download/0.5.0-hotfix/AtlasPlaybook_v0.5.0-hotfix.apbx',
    ),
    Playbook(
      name: 'RapidOS',
      description:
          'RapidOS Playbook - Lightweight, gaming-focused Windows configuration',
      downloadUrl:
          'https://github.com/rapid-community/RapidOS/releases/latest/download/RapidOS.apbx',
    ),
    Playbook(
      name: 'AtmosphereOS',
      description:
          'Atmosphere Playbook - Modular Windows configuration built on AtlasOS foundations',
      downloadUrl:
          'https://github.com/AtmosphereTeam/AtmosphereOS/releases/latest/download/AtmosphereOS.apbx',
    ),
  ];
}
