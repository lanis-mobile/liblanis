import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import '../../exceptions.dart';
import '../../models/datastorage.dart';
import '../applet_context.dart';
import '../applet_parser.dart';
import '../definition.dart';

class DataStorageParser
    extends AppletParser<(List<FileNode>, List<FolderNode>)> {
  DataStorageParser(
    AppletContext ctx, {
    Future<bool> Function()? isConnected,
  }) : super(
         ctx,
         Applets.dataStorage,
         isConnected:
             isConnected ?? () => ctx.session.connectionChecker.connected,
       );

  @override
  Future<(List<FileNode>, List<FolderNode>)> getHome() {
    return getRoot();
  }

  Future<dynamic> searchFiles(String query) async {
    final Response<dynamic> response;
    try {
      response = await ctx.session.dio.get(
        'https://start.schulportal.hessen.de/dateispeicher.php',
        queryParameters: {'q': query, 'a': 'searchFiles'},
      );
    } on DioException catch (e, stack) {
      Error.throwWithStackTrace(NetworkException.fromError(e, stack), stack);
    }
    if (response.statusCode == 302) {
      throw UnauthorizedException('Data storage search redirected');
    }
    final dynamic data;
    if (response.data is List) {
      data = response.data;
    } else {
      final body = response.data?.toString() ?? '';
      if (body.trim().isEmpty) return const <dynamic>[];
      data = jsonDecode(body);
    }
    if (data is List && data.isNotEmpty) {
      return data[0];
    }
    return const <dynamic>[];
  }

  Future<(List<FileNode>, List<FolderNode>)> getNode(int nodeID) async {
    late final Response response;
    try {
      response = await ctx.session.dio.get(
        "https://start.schulportal.hessen.de/dateispeicher.php?a=view&folder=$nodeID",
      );
    } catch (e) {
      throw NoConnectionException();
    }

    var document = parse(response.data);
    List<FileNode> files = [];
    List<String> headers = document
        .querySelectorAll("table#files thead th")
        .map((e) => e.text)
        .toList();
    for (var file in document.querySelectorAll("table#files tbody tr")) {
      final fields = file.querySelectorAll("td");
      String? hinweis = fields[headers.indexOf("Name")]
          .querySelector("small")
          ?.text
          .trim();
      if (hinweis != null) {
        fields[headers.indexOf("Name")].querySelector("small")?.text = "";
      }
      var name = fields[headers.indexOf("Name")].text.trim();
      var aenderung = fields[headers.indexOf("Änderung")].text.trim();
      var groesse = fields[headers.indexOf("Größe")].text.trim();
      var id = int.parse(file.attributes["data-id"]!.trim());
      files.add(
        FileNode(
          name: name,
          id: id,
          downloadUrl:
              "https://start.schulportal.hessen.de/dateispeicher.php?a=download&f=$id",
          aenderung: aenderung,
          groesse: groesse,
          hinweis: hinweis,
        ),
      );
    }

    List<FolderNode> folders = [];
    for (var folder in document.querySelectorAll(".folder")) {
      var name = folder.querySelector(".caption")!.text.trim();
      var desc = folder.querySelector(".desc")!.text.trim();
      var subfolders =
          int.tryParse(
            RegExp(r"\d+")
                    .firstMatch(
                      folder
                              .querySelector("[title=\"Anzahl Ordner\"]")
                              ?.text
                              .trim() ??
                          "",
                    )
                    ?.group(0) ??
                "",
          ) ??
          0;
      var id = int.parse(folder.attributes["data-id"]!);
      folders.add(FolderNode(name, id, subfolders, desc));
    }
    return (files, folders);
  }

  Future<(List<FileNode>, List<FolderNode>)> getRoot() async {
    return await getNode(0);
  }
}
