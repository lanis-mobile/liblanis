/// Data models for the SPH `dateiverteilung.php` applet.
library;

/// Target audience for a file distribution (Tooladmin form `Userart`).
enum DistributionAudience {
  students('Schueler'),
  parents('Eltern'),
  studentsAndParents('SchuelerEltern'),
  teachers('Lehrer');

  final String portalValue;
  const DistributionAudience(this.portalValue);

  static DistributionAudience fromPortalValue(String value) {
    return DistributionAudience.values.firstWhere(
      (e) => e.portalValue.toLowerCase() == value.trim().toLowerCase(),
      orElse: () => DistributionAudience.students,
    );
  }
}

/// Distribution mode (Tooladmin form `Einzeldatei`).
enum DistributionMode {
  /// Same file(s) distributed to every recipient (`nein`).
  sharedFiles('nein'),

  /// Individual random file per recipient (`ja`).
  randomSingle('ja'),

  /// Notice text and optional link only, no files (`keine`).
  textOnly('keine'),

  /// Personalized placeholder file plus optional additional files (`platzhalter`).
  placeholder('platzhalter');

  final String portalValue;
  const DistributionMode(this.portalValue);

  static DistributionMode fromPortalValue(String value) {
    return DistributionMode.values.firstWhere(
      (e) => e.portalValue.toLowerCase() == value.trim().toLowerCase(),
      orElse: () => DistributionMode.sharedFiles,
    );
  }
}

/// Top-level overview returned by `GET dateiverteilung.php`.
class FileDistributionHome {
  /// Distributions addressed to the logged-in account.
  final List<FileDistributionItem> items;

  /// Whether this account has Tooladmin access (`dateiverteilung.php?a=admin`).
  final bool isAdmin;

  /// Quick-access files shown in the Tooladmin sidebar (empty for non-admins).
  final List<ToolAdminQuickDistribution> adminSidebarItems;

  const FileDistributionHome({
    required this.items,
    this.isAdmin = false,
    this.adminSidebarItems = const [],
  });

  Map<String, dynamic> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'isAdmin': isAdmin,
    'adminSidebarItems': [for (final item in adminSidebarItems) item.toJson()],
  };

  factory FileDistributionHome.fromJson(Map<String, dynamic> json) {
    return FileDistributionHome(
      items: [
        for (final raw in (json['items'] as List? ?? const []))
          FileDistributionItem.fromJson(Map<String, dynamic>.from(raw as Map)),
      ],
      isAdmin: json['isAdmin'] as bool? ?? false,
      adminSidebarItems: [
        for (final raw in (json['adminSidebarItems'] as List? ?? const []))
          ToolAdminQuickDistribution.fromJson(
            Map<String, dynamic>.from(raw as Map),
          ),
      ],
    );
  }
}

/// A single distribution card shown to a recipient.
class FileDistributionItem {
  final int id;
  final String title;
  final DateTime? validFrom;
  final DateTime? validUntil;

  /// Resolved notice/description text (placeholders already expanded by SPH).
  final String? description;
  final String? creatorName;

  /// Whether the "Neu" badge is shown on this distribution.
  final bool isUnread;

  /// Whether the card exposes a `.read` action to dismiss without downloading.
  final bool canMarkAsRead;

  /// Optional server-side error badge in `.panel-footer > .label-danger`.
  final String? errorMessage;

  /// Optional external info link (`LinkUrl` / `LinkTitel`).
  final FileDistributionLink? infoLink;

  /// Downloadable files attached to this distribution (empty for text-only).
  final List<FileDistributionFile> files;

  const FileDistributionItem({
    required this.id,
    required this.title,
    this.validFrom,
    this.validUntil,
    this.description,
    this.creatorName,
    this.isUnread = false,
    this.canMarkAsRead = false,
    this.errorMessage,
    this.infoLink,
    this.files = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'validFrom': validFrom?.toIso8601String(),
    'validUntil': validUntil?.toIso8601String(),
    'description': description,
    'creatorName': creatorName,
    'isUnread': isUnread,
    'canMarkAsRead': canMarkAsRead,
    'errorMessage': errorMessage,
    'infoLink': infoLink?.toJson(),
    'files': [for (final f in files) f.toJson()],
  };

  factory FileDistributionItem.fromJson(Map<String, dynamic> json) {
    return FileDistributionItem(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '',
      validFrom: json['validFrom'] != null
          ? DateTime.parse(json['validFrom'] as String)
          : null,
      validUntil: json['validUntil'] != null
          ? DateTime.parse(json['validUntil'] as String)
          : null,
      description: json['description'] as String?,
      creatorName: json['creatorName'] as String?,
      isUnread: json['isUnread'] as bool? ?? false,
      canMarkAsRead: json['canMarkAsRead'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
      infoLink: json['infoLink'] != null
          ? FileDistributionLink.fromJson(
              Map<String, dynamic>.from(json['infoLink'] as Map),
            )
          : null,
      files: [
        for (final raw in (json['files'] as List? ?? const []))
          FileDistributionFile.fromJson(Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }
}

/// Optional external info link attached to a distribution.
class FileDistributionLink {
  final Uri url;
  final String title;

  const FileDistributionLink({required this.url, required this.title});

  Map<String, dynamic> toJson() => {'url': url.toString(), 'title': title};

  factory FileDistributionLink.fromJson(Map<String, dynamic> json) {
    return FileDistributionLink(
      url: Uri.parse(json['url'] as String),
      title: json['title'] as String? ?? '',
    );
  }
}

/// A single downloadable file inside a distribution.
class FileDistributionFile {
  /// Portal `k` index (`data-id` on `.verteilungmulti`).
  final int index;
  final String name;
  final Uri downloadUrl;
  final bool isTemplate;

  const FileDistributionFile({
    required this.index,
    required this.name,
    required this.downloadUrl,
    this.isTemplate = false,
  });

  String get fileExtension {
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1 ? name.substring(dot + 1) : '';
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'name': name,
    'downloadUrl': downloadUrl.toString(),
    'isTemplate': isTemplate,
  };

  factory FileDistributionFile.fromJson(Map<String, dynamic> json) {
    return FileDistributionFile(
      index: (json['index'] as num).toInt(),
      name: json['name'] as String? ?? '',
      downloadUrl: Uri.parse(json['downloadUrl'] as String),
      isTemplate: json['isTemplate'] as bool? ?? false,
    );
  }
}

/// Quick-access distribution shown in the Tooladmin sidebar on `dateiverteilung.php`.
class ToolAdminQuickDistribution {
  final int id;
  final String title;
  final String? audienceLabel;
  final List<FileDistributionFile> files;

  const ToolAdminQuickDistribution({
    required this.id,
    required this.title,
    this.audienceLabel,
    this.files = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'audienceLabel': audienceLabel,
    'files': [for (final f in files) f.toJson()],
  };

  factory ToolAdminQuickDistribution.fromJson(Map<String, dynamic> json) {
    return ToolAdminQuickDistribution(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '',
      audienceLabel: json['audienceLabel'] as String?,
      files: [
        for (final raw in (json['files'] as List? ?? const []))
          FileDistributionFile.fromJson(Map<String, dynamic>.from(raw as Map)),
      ],
    );
  }
}

/// Summary row from the Tooladmin table (`GET dateiverteilung.php?a=admin`).
class AdminFileDistributionSummary {
  final int id;
  final String title;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String audienceLabel;
  final DistributionMode mode;
  final int distributedCount;
  final int totalRecipients;
  final List<FileDistributionFile> files;
  final bool filesAvailable;
  final String? creatorName;
  final String? creatorShortName;
  final bool canUpload;

  const AdminFileDistributionSummary({
    required this.id,
    required this.title,
    this.validFrom,
    this.validUntil,
    required this.audienceLabel,
    required this.mode,
    required this.distributedCount,
    required this.totalRecipients,
    this.files = const [],
    this.filesAvailable = false,
    this.creatorName,
    this.creatorShortName,
    this.canUpload = false,
  });
}

/// Full metadata returned by `POST dateiverteilung.php` (`a=admin&f=edit&v=<id>`).
class AdminFileDistributionDetail {
  final int id;
  final String title;
  final String description;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? filesDeleteAt;
  final DistributionAudience audience;
  final int? gradeFrom;
  final int? gradeUntil;
  final DistributionMode mode;
  final List<String> fileNameTemplates;
  final int? startNumber;
  final FileDistributionLink? infoLink;
  final int fileCount;
  final int consumedCount;
  final DateTime? createdAt;
  final String? creatorId;
  final String? creatorName;
  final String? creatorShortName;

  const AdminFileDistributionDetail({
    required this.id,
    required this.title,
    required this.description,
    this.validFrom,
    this.validUntil,
    this.filesDeleteAt,
    required this.audience,
    this.gradeFrom,
    this.gradeUntil,
    required this.mode,
    this.fileNameTemplates = const [],
    this.startNumber,
    this.infoLink,
    this.fileCount = 0,
    this.consumedCount = 0,
    this.createdAt,
    this.creatorId,
    this.creatorName,
    this.creatorShortName,
  });
}

/// Payload for creating or updating a distribution via `POST a=admin&f=new`.
class FileDistributionDraft {
  /// Leave `null` when creating a new distribution; set to update an existing one.
  final int? id;
  final String title;
  final DistributionAudience audience;
  final int? gradeFrom;
  final int? gradeUntil;
  final String description;
  final DateTime validFrom;
  final DateTime validUntil;
  final DistributionMode mode;
  final String? fileNameTemplate;
  final int? startNumber;
  final Uri? linkUrl;
  final String? linkTitle;

  const FileDistributionDraft({
    this.id,
    required this.title,
    required this.audience,
    this.gradeFrom,
    this.gradeUntil,
    this.description = '',
    required this.validFrom,
    required this.validUntil,
    required this.mode,
    this.fileNameTemplate,
    this.startNumber,
    this.linkUrl,
    this.linkTitle,
  });
}

/// Retrieval statistics from `GET dateiverteilung.php?a=admin&f=chart&v=<id>`.
class FileDistributionStats {
  final int distributionId;
  final String title;
  final List<FileDistributionGroupStat> groups;
  final FileDistributionGroupStat? total;

  const FileDistributionStats({
    required this.distributionId,
    required this.title,
    required this.groups,
    this.total,
  });
}

/// Single row in the retrieval statistics table.
class FileDistributionGroupStat {
  final String group;
  final int retrieved;
  final int pending;
  final double completionPercent;

  const FileDistributionGroupStat({
    required this.group,
    required this.retrieved,
    required this.pending,
    required this.completionPercent,
  });
}
