// ==UserScript==
// @name         example.com 专用脚本
// @namespace    mh.iphone6.native
// @version      1.0.0
// @description  只在 example.com 上运行，用来验证 @match 精确匹配与 GM.* 异步 API
// @match        *://example.com/*
// @match        *://www.example.com/*
// @run-at       document-end
// @grant        GM_addStyle
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @grant        GM_notification
// @grant        GM_log
// ==/UserScript==
(function () {
  'use strict';
  var visits = (GM_getValue('visits', 0) || 0) + 1;
  GM_setValue('visits', visits);
  GM.setValue('lastVisit', new Date().toISOString());
  GM_log('example.com 专用脚本第 ' + visits + ' 次运行');

  GM_addStyle([
    '.ip6-native-banner{background:#2f6bff;color:#fff;padding:10px 16px;',
    'font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;text-align:center}'
  ].join(''));

  var banner = document.createElement('div');
  banner.className = 'ip6-native-banner';
  banner.textContent = '已由原生 WKWebView 注入 · 第 ' + visits + ' 次运行（@match 精确匹配生效）';
  document.body.insertBefore(banner, document.body.firstChild);

  GM_registerMenuCommand('example.com：显示访问次数', function () {
    GM_notification({ title: '访问次数', text: '已运行 ' + visits + ' 次' });
  });
})();
