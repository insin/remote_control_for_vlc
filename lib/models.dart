class BrowseItem {
  String type, name, path, uri;

  BrowseItem(this.type, this.name, this.path, this.uri);

  BrowseItem.fromJson(Map<String, dynamic> json)
      : type = json['type'],
        name = json['name'],
        path = json['path'],
        uri = json['uri'];

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'path': path,
        'uri': uri,
      };
}
