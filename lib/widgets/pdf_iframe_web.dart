import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

Widget buildPdfIframe(String url) {
  final String viewId = 'pdf-iframe-${url.hashCode}';
  
  // Register the view factory
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int viewId) => html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%',
  );

  return HtmlElementView(viewType: viewId);
}

