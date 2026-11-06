/* iPhone6 Browser native userscript runtime.
 * Injected once at documentStart via WKUserScript. Each userscript gets its own
 * API object from __tm_makeApi(), so GM_* never leak between scripts. */
(function () {
  'use strict';

  var seq = 0;
  var menuMap = Object.create(null);
  var xhrMap = Object.create(null);

  function bridge() {
    return window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gm;
  }
  function post(obj) {
    try { var h = bridge(); if (h) h.postMessage(obj); } catch (e) {}
  }
  function stringify(v) {
    if (typeof v === 'string') return v;
    if (v instanceof Error) return v.stack || v.message;
    try { return JSON.stringify(v); } catch (e) { return String(v); }
  }
  function log(level, text) { post({ op: 'log', level: level, text: String(text) }); }
  function safe(v) {
    if (v === null || v === undefined) return null;
    var t = typeof v;
    if (t === 'string' || t === 'number' || t === 'boolean') return v;
    try { return JSON.parse(JSON.stringify(v)); } catch (e) { return String(v); }
  }

  // Forward page console output to the native console panel.
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
    var original = console[level];
    console[level] = function () {
      try { log(level, Array.prototype.map.call(arguments, stringify).join(' ')); } catch (e) {}
      return original && original.apply(console, arguments);
    };
  });
  window.addEventListener('error', function (e) {
    log('error', '[page] ' + (e.message || 'error') + ' @ ' + (e.filename || '') + ':' + (e.lineno || 0));
  });
  window.addEventListener('unhandledrejection', function (e) {
    log('error', '[promise] ' + stringify(e.reason));
  });

  // Called by Swift when a GM_xmlhttpRequest finishes.
  window.__tm_xhrCallback = function (id, ok, res) {
    var d = xhrMap[String(id)];
    if (!d) return;
    delete xhrMap[String(id)];
    res = res || {};
    var x = {
      status: res.status || 0,
      statusText: res.statusText || '',
      readyState: 4,
      responseText: res.text || '',
      response: res.text || '',
      responseHeaders: res.headers || '',
      finalUrl: res.finalUrl || d.url,
      context: d.context
    };
    try { if (d.onreadystatechange) d.onreadystatechange(x); } catch (e) {}
    if (ok) { try { if (d.onload) d.onload(x); } catch (e) { log('error', '[onload] ' + e.message); } }
    else { try { if (d.onerror) d.onerror({ error: res.error || 'request failed', status: res.status || 0 }); } catch (e) {} }
    try { if (d.onloadend) d.onloadend(x); } catch (e) {}
  };

  // Called by Swift when the user taps a registered menu command.
  window.__tm_menuClick = function (id) {
    var fn = menuMap[String(id)];
    if (!fn) return;
    try { fn(); } catch (e) { log('error', '[menu] ' + (e.stack || e.message)); }
  };

  window.__tm_makeApi = function (P) {
    var values = P.values || {};
    var resources = P.resources || {};
    var tab = Object.create(null);
    var listeners = Object.create(null);
    var api = {};

    function base(op) { return { op: op, ns: P.ns, scriptId: P.scriptId, name: P.name }; }

    api.unsafeWindow = window;
    api.GM_info = P.info || {};

    api.GM_log = function () {
      log('log', '[' + P.name + '] ' + Array.prototype.map.call(arguments, stringify).join(' '));
    };
    api.GM_setValue = function (key, value) {
      values[String(key)] = value;
      var m = base('setValue'); m.key = String(key); m.value = safe(value); post(m);
    };
    api.GM_getValue = function (key, fallback) {
      return Object.prototype.hasOwnProperty.call(values, String(key)) ? values[String(key)] : fallback;
    };
    api.GM_deleteValue = function (key) {
      delete values[String(key)];
      var m = base('deleteValue'); m.key = String(key); post(m);
    };
    api.GM_listValues = function () { return Object.keys(values); };
    api.GM_addValueChangeListener = function (key, fn) {
      var id = ++seq;
      var last = api.GM_getValue(key);
      listeners[String(id)] = setInterval(function () {
        var now = api.GM_getValue(key);
        if (JSON.stringify(now) !== JSON.stringify(last)) {
          var old = last; last = now;
          try { fn(String(key), old, now, false); } catch (e) {}
        }
      }, 800);
      return id;
    };
    api.GM_removeValueChangeListener = function (id) {
      clearInterval(listeners[String(id)]);
      delete listeners[String(id)];
    };
    api.GM_addStyle = function (css) {
      var style = document.createElement('style');
      style.setAttribute('data-tm-style', '1');
      style.textContent = String(css);
      (document.head || document.documentElement).appendChild(style);
      return style;
    };
    api.GM_getResourceText = function (name) { return resources[name] || ''; };
    api.GM_getResourceURL = function (name) {
      var text = resources[name] || '';
      try { return 'data:application/octet-stream;base64,' + btoa(unescape(encodeURIComponent(text))); }
      catch (e) { return ''; }
    };
    api.GM_xmlhttpRequest = function (d) {
      if (!d || !d.url) throw new Error('GM_xmlhttpRequest: url is required');
      var id = ++seq;
      xhrMap[String(id)] = d;
      var m = base('xhr');
      m.id = id;
      m.url = String(d.url);
      m.method = String(d.method || 'GET').toUpperCase();
      m.headers = safe(d.headers || {});
      m.data = d.data === undefined ? null : safe(d.data);
      m.timeout = Number(d.timeout) || 20000;
      m.user = d.user || null;
      m.password = d.password || null;
      log('info', '[GM_xmlhttpRequest] ' + m.method + ' ' + m.url);
      post(m);
      return { abort: function () { delete xhrMap[String(id)]; var a = base('xhrAbort'); a.id = id; post(a); } };
    };
    api.GM_registerMenuCommand = function (name, fn, options) {
      var id = ++seq;
      menuMap[String(id)] = fn;
      var m = base('menu');
      m.id = id;
      m.text = String(name);
      m.accessKey = (options && options.accessKey) || '';
      post(m);
      return id;
    };
    api.GM_unregisterMenuCommand = function (id) {
      delete menuMap[String(id)];
      var m = base('menuRemove'); m.id = id; post(m);
    };
    api.GM_notification = function (a, b) {
      var o = (a && typeof a === 'object') ? a : { title: String(a), text: String(b || '') };
      var m = base('notify');
      m.title = o.title || '油猴脚本';
      m.text = o.text || '';
      m.timeout = Number(o.timeout) || 3500;
      post(m);
      return function () {};
    };
    api.GM_openInTab = function (url, options) {
      var m = base('openTab');
      m.url = String(url);
      m.active = !options || options.active !== false;
      post(m);
      return { close: function () {} };
    };
    api.GM_setClipboard = function (text, info) {
      var m = base('clipboard'); m.text = String(text); post(m);
      var ta = document.createElement('textarea');
      ta.value = String(text);
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      (document.body || document.documentElement).appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); } catch (e) {}
      ta.remove();
    };
    api.GM_download = function (a, b) {
      var o = (a && typeof a === 'object') ? a : { url: String(a), name: String(b || 'download') };
      var m = base('download'); m.url = String(o.url); m.name = o.name || 'download'; post(m);
    };
    api.GM_getTab = function (cb) { cb(tab); };
    api.GM_saveTab = function (obj) { tab = obj || {}; };
    api.GM_getTabs = function (cb) { var o = {}; o[P.scriptId] = tab; cb(o); };

    var GM = { info: api.GM_info };
    ['setValue', 'getValue', 'deleteValue', 'listValues', 'addStyle', 'getResourceText']
      .forEach(function (n) {
        GM[n] = function () { return Promise.resolve(api['GM_' + n].apply(null, arguments)); };
      });
    GM.getResourceUrl = GM.getResourceURL = function (n) { return Promise.resolve(api.GM_getResourceURL(n)); };
    GM.notification = function (a, b) { return Promise.resolve(api.GM_notification(a, b)); };
    GM.openInTab = function (u, o) { return Promise.resolve(api.GM_openInTab(u, o)); };
    GM.setClipboard = function (t) { return Promise.resolve(api.GM_setClipboard(t)); };
    GM.download = function (a, b) { return Promise.resolve(api.GM_download(a, b)); };
    GM.registerMenuCommand = function (n, f, o) { return Promise.resolve(api.GM_registerMenuCommand(n, f, o)); };
    GM.unregisterMenuCommand = function (i) { return Promise.resolve(api.GM_unregisterMenuCommand(i)); };
    GM.log = function () { return Promise.resolve(api.GM_log.apply(null, arguments)); };
    GM.xmlHttpRequest = GM.xmlhttpRequest = function (d) {
      return new Promise(function (resolve, reject) {
        var onload = d.onload, onerror = d.onerror;
        d.onload = function (x) { if (onload) onload(x); resolve(x); };
        d.onerror = function (e) { if (onerror) onerror(e); reject(e); };
        api.GM_xmlhttpRequest(d);
      });
    };
    api.GM = GM;
    return api;
  };
})();
