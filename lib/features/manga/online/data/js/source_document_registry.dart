import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// JS 侧 `HtmlDocument` 的宿主句柄表。
///
/// 源在 QuickJS 里同步调用 `doc.querySelector(...)`，所以这里不能返回 Future；
/// 每次查询把节点放进数组，只把整数句柄交给 JS。文档上限 8 份，按最早创建淘汰。
class SourceDocumentRegistry {
  SourceDocumentRegistry({this.maxDocuments = 8});

  final int maxDocuments;
  final Map<int, _DocumentHandles> _documents = {};

  Object? handle(Map<String, dynamic> message) {
    final function = message['function'];
    if (function == 'parse') {
      final key = _int(message['key']);
      if (_documents.length >= maxDocuments) {
        _documents.remove(_documents.keys.first);
      }
      _documents[key] = _DocumentHandles.parse('${message['data'] ?? ''}');
      return {'ok': true};
    }
    if (function == 'dispose') {
      _documents.remove(_int(message['key']));
      return {'ok': true};
    }
    final doc = _documents[_int(message['doc'] ?? message['key'])];
    if (doc == null) return {'error': 'document_not_found'};
    try {
      switch (function) {
        case 'querySelector':
          return doc.documentQuerySelector('${message['query'] ?? ''}');
        case 'querySelectorAll':
          return doc.documentQuerySelectorAll('${message['query'] ?? ''}');
        case 'getElementById':
          return doc.getElementById('${message['id'] ?? ''}');
        case 'getText':
          return doc.elementText(_int(message['key']));
        case 'getAttributes':
          return doc.elementAttributes(_int(message['key']));
        case 'getInnerHTML':
          return doc.elementInnerHtml(_int(message['key']));
        case 'getChildren':
          return doc.elementChildren(_int(message['key']));
        case 'getParent':
          return doc.elementParent(_int(message['key']));
        case 'getPreviousSibling':
          return doc.elementPreviousSibling(_int(message['key']));
        case 'getNextSibling':
          return doc.elementNextSibling(_int(message['key']));
        case 'getClassNames':
          return doc.elementClassNames(_int(message['key']));
        case 'getId':
          return doc.elementId(_int(message['key']));
        case 'getLocalName':
          return doc.elementLocalName(_int(message['key']));
        case 'dom_querySelector':
          return doc.elementQuerySelector(_int(message['key']), '${message['query'] ?? ''}');
        case 'dom_querySelectorAll':
          return doc.elementQuerySelectorAll(_int(message['key']), '${message['query'] ?? ''}');
        case 'getNodes':
          return doc.elementNodes(_int(message['key']));
        case 'node_text':
          return doc.nodeText(_int(message['key']));
        case 'node_type':
          return doc.nodeType(_int(message['key']));
        case 'node_toElement':
          return doc.nodeToElement(_int(message['key']));
      }
    } catch (e) {
      return {'error': 'query_failed: $e'};
    }
    return null;
  }

  void clear() => _documents.clear();

  static int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

class _DocumentHandles {
  _DocumentHandles(this.document);

  factory _DocumentHandles.parse(String raw) => _DocumentHandles(html.parse(raw));

  final dom.Document document;
  final List<dom.Element> elements = [];
  final List<dom.Node> nodes = [];

  int _addElement(dom.Element element) {
    elements.add(element);
    return elements.length - 1;
  }

  int? documentQuerySelector(String query) {
    final element = document.querySelector(query);
    return element == null ? null : _addElement(element);
  }

  List<int> documentQuerySelectorAll(String query) => document.querySelectorAll(query).map(_addElement).toList();

  int? getElementById(String id) {
    final element = document.getElementById(id);
    return element == null ? null : _addElement(element);
  }

  dom.Element? _element(int key) => key >= 0 && key < elements.length ? elements[key] : null;

  String elementText(int key) => _element(key)?.text ?? '';

  Map<String, String> elementAttributes(int key) =>
      (_element(key)?.attributes ?? const {}).map((key, value) => MapEntry('$key', '$value'));

  String? elementInnerHtml(int key) => _element(key)?.innerHtml;

  List<int> elementChildren(int key) => (_element(key)?.children ?? const []).map(_addElement).toList();

  int? elementParent(int key) {
    final parent = _element(key)?.parent;
    return parent == null ? null : _addElement(parent);
  }

  int? elementPreviousSibling(int key) {
    final sibling = _element(key)?.previousElementSibling;
    return sibling == null ? null : _addElement(sibling);
  }

  int? elementNextSibling(int key) {
    final sibling = _element(key)?.nextElementSibling;
    return sibling == null ? null : _addElement(sibling);
  }

  List<String> elementClassNames(int key) => _element(key)?.classes.toList() ?? const [];

  String? elementId(int key) => _element(key)?.id;

  String? elementLocalName(int key) => _element(key)?.localName;

  int? elementQuerySelector(int key, String query) {
    final element = _element(key)?.querySelector(query);
    return element == null ? null : _addElement(element);
  }

  List<int> elementQuerySelectorAll(int key, String query) =>
      (_element(key)?.querySelectorAll(query) ?? const []).map(_addElement).toList();

  List<int> elementNodes(int key) {
    final result = <int>[];
    for (final node in _element(key)?.nodes ?? const <dom.Node>[]) {
      nodes.add(node);
      result.add(nodes.length - 1);
    }
    return result;
  }

  String nodeText(int key) => key >= 0 && key < nodes.length ? nodes[key].text ?? '' : '';

  String nodeType(int key) {
    if (key < 0 || key >= nodes.length) return 'unknown';
    return switch (nodes[key].nodeType) {
      dom.Node.ELEMENT_NODE => 'element',
      dom.Node.TEXT_NODE => 'text',
      dom.Node.COMMENT_NODE => 'comment',
      dom.Node.DOCUMENT_NODE => 'document',
      _ => 'unknown',
    };
  }

  int? nodeToElement(int key) {
    if (key < 0 || key >= nodes.length) return null;
    final node = nodes[key];
    return node is dom.Element ? _addElement(node) : null;
  }
}
