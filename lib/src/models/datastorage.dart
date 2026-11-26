enum FileActions { download, upload, delete }

/// A single entry in the `dateispeicher.php` folder breadcrumb trail.
class FolderBreadcrumb {
  final int id;
  final String name;

  const FolderBreadcrumb({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderBreadcrumb && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'FolderBreadcrumb(id: $id, name: $name)';
}

/// Full parsed representation of a `dateispeicher.php?a=view&folder=<id>` page.
class DataStorageNode {
  final int id;
  final String name;
  final List<FolderBreadcrumb> breadcrumbs;
  final List<FileNode> files;
  final List<FolderNode> folders;

  /// Recently added files shown in the "Neue Dateien" sidebar (typically on root).
  final List<FileNode> newFiles;

  /// Whether the page exposes the "Admin-Ansicht" toggle (`#adminView`).
  final bool canAdminView;

  const DataStorageNode({
    required this.id,
    required this.name,
    this.breadcrumbs = const [],
    this.files = const [],
    this.folders = const [],
    this.newFiles = const [],
    this.canAdminView = false,
  });

  /// Ancestor breadcrumbs excluding the current folder itself (empty at root).
  List<FolderBreadcrumb> get parentBreadcrumbs => breadcrumbs.length > 1
      ? List.unmodifiable(breadcrumbs.sublist(0, breadcrumbs.length - 1))
      : const [];
}

class FileNode {
  final String name;
  int id;
  int? folderID;
  String downloadUrl;
  String groesse;
  String aenderung;
  String? hinweis;

  /// Server-reported file extension from `data-ext` (e.g. `pdf`, `png`).
  String? extension;

  /// Parsed modification timestamp from the `Änderung` column, if available.
  DateTime? modifiedAt;

  /// Parsed file size in bytes from the `Größe` column, if available.
  int? sizeBytes;

  List<FileActions> supportedActions = [FileActions.download];

  FileNode({
    required this.name,
    required this.id,
    required this.downloadUrl,
    this.aenderung = "",
    this.groesse = "",
    this.hinweis,
    this.folderID,
    this.extension,
    this.modifiedAt,
    this.sizeBytes,
  });

  String get fileExtension {
    final ext = extension?.trim();
    if (ext != null && ext.isNotEmpty) return ext;
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1 ? name.substring(dot + 1) : '';
  }
}

class FolderNode {
  String name;
  int id;
  int subfolders;
  String desc;

  /// Number of files reported by the folder card, if present (`0` for "Keine Dateien").
  int? fileCount;

  /// Custom hex color from the folder card's inline border/link style (e.g. `#000000`).
  String? colorHex;

  /// Whether the folder link indicates write access (`data-wx="yes"`).
  bool canWrite;

  FolderNode(
    this.name,
    this.id,
    this.subfolders,
    this.desc, {
    this.fileCount,
    this.colorHex,
    this.canWrite = false,
  });
}
