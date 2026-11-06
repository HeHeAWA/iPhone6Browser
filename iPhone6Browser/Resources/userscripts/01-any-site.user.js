// ==UserScript==
// @name         全站注入标记（任意真实网站）
// @namespace    mh.iphone6.native
// @version      1.0.0
// @description  验证 WKUserScript 注入、GM 存储、菜单命令、通知与跨域请求
// @author       iPhone6 Browser Native
// @match        *://*/*
// @run-at       document-end
// @grant        GM_addStyle
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_listValues
// @grant        GM_registerMenuCommand
// @grant        GM_notification
// @grant        GM_xmlhttpRequest
// @grant        GM_openInTab
// @grant        GM_setClipboard
// @grant        GM_log
// @grant        GM_info
// ==/UserScript==
(function () {
  'use strict';
  if (document.getElementById('__ip6_native_badge__')) return;

  var hits = (GM_getValue('pageHits', 0) || 0) + 1;
  GM_setValue('pageHits', hits);
  GM_log('已注入：' + location.href);
  GM_log('GM_info.scriptHandler = ' + GM_info.scriptHandler +
         '；存储键 = ' + GM_listValues().join(', '));

  GM_addStyle([
    '#__ip6_native_badge__{position:fixed;right:8px;bottom:8px;z-index:2147483647;',
    'display:flex;align-items:center;gap:5px;padding:5px 9px;border-radius:999px;',
    'background:rgba(30,42,72,.86);color:#fff;',
    'font:11px/1.2 -apple-system,BlinkMacSystemFont,sans-serif;',
    'box-shadow:0 3px 12px rgba(0,0,0,.22);opacity:.75}',
    '#__ip6_native_badge__ i{width:6px;height:6px;border-radius:50%;background:#4ade80;display:block}'
  ].join(''));

  var badge = document.createElement('div');
  badge.id = '__ip6_native_badge__';
  badge.title = '原生 WKWebView 注入成功';
  badge.innerHTML = '<i></i><span>脚本已注入</span>';
  (document.body || document.documentElement).appendChild(badge);

  GM_registerMenuCommand('测试通知', function () {
    GM_notification({ title: 'iPhone 6 Browser', text: '当前站点：' + location.host, timeout: 3000 });
  });
  GM_registerMenuCommand('跨域请求自检', function () {
    GM_xmlhttpRequest({
      method: 'GET',
      url: 'https://example.com/',
      onload: function (r) {
        GM_log('GM_xmlhttpRequest 自检通过 HTTP ' + r.status);
        GM_notification({ title: '跨域请求成功', text: 'HTTP ' + r.status + ' · ' + r.finalUrl });
      },
      onerror: function (e) { GM_log('跨域请求失败：' + (e.error || 'unknown')); }
    });
  });
  GM_registerMenuCommand('复制当前网址', function () { GM_setClipboard(location.href); });
  GM_registerMenuCommand('打开新标签页', function () { GM_openInTab('https://example.com/', { active: true }); });
})();
