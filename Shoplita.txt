// ==UserScript==
// @name         Shoplita
// @namespace    shoplita
// @version      2.13.0
// @description  Saves prices and pieces from lolita shops (42Lolita, Devilinspired, My-Lolita-Dress, AliExpress and other pages) into one wishlist. Keeps dated snapshots, computes coordinated set totals, ranks favourites, marks availability, organizes items into named sets and saves mix-and-match outfits, exports/imports JSON, TSV, Excel-ready CSV and Shoplita share files, and compares items, sets and outfits with searchable pickers, images and live totals in a minimizable panel.
// @author       tan
// @match        https://42lolita.com/*
// @match        https://www.42lolita.com/*
// @match        https://devilinspired.com/*
// @match        https://www.devilinspired.com/*
// @match        https://my-lolita-dress.com/*
// @match        https://www.my-lolita-dress.com/*
// @match        https://*.aliexpress.com/*
// @match        https://*.aliexpress.us/*
// @grant        GM_setClipboard
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @inject-into  content
// @run-at       document-start
// @noframes
// ==/UserScript==

(function () {
  'use strict';

  var STORAGE_KEY = 'shoplita.savedInfo.v1';
  var PRIORITY_KEY = 'shoplita.priority.v1';
  var UNAVAILABLE_KEY = 'shoplita.unavailable.v1';
  var COMPARE_KEY = 'shoplita.compare.v1';
  var UI_KEY = 'shoplita.ui.v1';
  var COLLECTIONS_KEY = 'shoplita.collections.v1';
  var OUTFITS_KEY = 'shoplita.outfits.v1';

  var COLOR_WORDS = [
    'royal blue', 'sky blue', 'light blue', 'dark blue', 'navy blue', 'baby blue', 'powder blue',
    'wine red', 'dark red', 'light pink', 'hot pink', 'baby pink', 'rose pink', 'off white', 'off-white',
    'ivory white', 'dark green', 'light green', 'mint green', 'army green', 'dark brown', 'light brown',
    'grey blue', 'gray blue', 'champagne gold', 'rose gold', 'dark purple', 'light purple',
    'wine', 'burgundy', 'maroon', 'navy', 'blue', 'pink', 'black', 'white', 'red', 'green', 'purple',
    'yellow', 'brown', 'grey', 'gray', 'beige', 'apricot', 'lavender', 'mint', 'teal', 'orange', 'gold',
    'silver', 'rose', 'ivory', 'khaki', 'coffee', 'sakura', 'peach', 'cream', 'champagne', 'lilac',
    'turquoise', 'coral', 'olive', 'mustard', 'chocolate', 'violet', 'indigo', 'cyan', 'magenta', 'pearl',
    'caramel', 'bronze', 'copper', 'aqua', 'periwinkle', 'cerulean'
  ].sort(function (a, b) { return b.length - a.length; });

  var SIZE_RE = /^(\d{2,3}|xxs|xs|s|m|l|xl|xxl|2xl|3xl|4xl|5xl|one size|free size)$/i;

  function escapeRegExp(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  var COLOR_RE = new RegExp('\\b(' + COLOR_WORDS.map(escapeRegExp).join('|') + ')\\b', 'i');

  function detectColor(text) {
    if (!text) return null;
    var m = String(text).match(COLOR_RE);
    if (!m) return null;
    return m[1].replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }

  function centsToNumber(cents) {
    return Math.round(Number(cents)) / 100;
  }

  function stripTags(html) {
    var div = document.createElement('div');
    div.innerHTML = html || '';
    return div.textContent || '';
  }

  function firstImage(value) {
    if (!value) return null;
    if (Array.isArray(value)) return firstImage(value[0]);
    if (typeof value === 'object') return value.url || value.src || value.contentUrl || null;
    return String(value);
  }

  function collectImages(value) {
    var out = [];
    if (Array.isArray(value)) {
      for (var i = 0; i < value.length && out.length < 6; i++) {
        var url = firstImage(value[i]);
        if (url && out.indexOf(url) < 0) out.push(url);
      }
    } else {
      var single = firstImage(value);
      if (single) out.push(single);
    }
    return out;
  }

  function productCodeFrom(description) {
    var m = stripTags(description).match(/Product code\s*:\s*([^\s]+)/i);
    return m ? m[1] : null;
  }

  function entryList(obj) {
    var out = [];
    for (var k in obj) {
      if (Object.prototype.hasOwnProperty.call(obj, k)) out.push([k, obj[k]]);
    }
    return out;
  }

  var PIECE_KEYWORDS = [
    ['mini top hat', 'Top Hat'],
    ['top hat', 'Top Hat'],
    ['waist cincher', 'Waist Cincher'],
    ['cincher', 'Waist Cincher'],
    ['wristcuff', 'Wrist Cuffs'],
    ['hairclip', 'Hair Clips'],
    ['ear clip', 'Ear Clips'],
    ['hairband', 'Headband'],
    ['headdress', 'Headdress'],
    ['headpiece', 'Headpiece'],
    ['headband', 'Headband'],
    ['underskirt', 'Underskirt'],
    ['overskirt', 'Overskirt'],
    ['undershirt', 'Undershirt'],
    ['petticoat', 'Petticoat'],
    ['pantyhose', 'Pantyhose'],
    ['stocking', 'Stockings'],
    ['bloomer', 'Bloomers'],
    ['blouse', 'Blouse'],
    ['shirt', 'Shirt'],
    ['skirt', 'Skirt'],
    ['jacket', 'Jacket'],
    ['cardigan', 'Cardigan'],
    ['corset', 'Corset'],
    ['bolero', 'Bolero'],
    ['camisole', 'Camisole'],
    ['salopette', 'Salopette'],
    ['mantle', 'Mantle'],
    ['jabot', 'Jabot'],
    ['bonnet', 'Bonnet'],
    ['bnt', 'Bonnet'],
    ['apron', 'Apron'],
    ['parasol', 'Parasol'],
    ['umbrella', 'Parasol'],
    ['choker', 'Choker'],
    ['necklace', 'Necklace'],
    ['brooch', 'Brooch'],
    ['badge', 'Badge'],
    ['sleeve', 'Sleeves'],
    ['glove', 'Gloves'],
    ['cuff', 'Cuffs'],
    ['sock', 'Socks'],
    ['boot', 'Boots'],
    ['shoe', 'Shoes'],
    ['tights', 'Tights'],
    ['veil', 'Veil'],
    ['belt', 'Belt'],
    ['chain', 'Chains'],
    ['streamer', 'Streamers'],
    ['clip', 'Hair Clips'],
    ['crown', 'Crown'],
    ['beret', 'Beret'],
    ['sash', 'Sash'],
    ['bow', 'Bow'],
    ['collar', 'Collar'],
    ['tie', 'Tie'],
    ['bag', 'Bag'],
    ['purse', 'Bag'],
    ['vest', 'Vest'],
    ['shorts', 'Shorts'],
    ['pants', 'Pants'],
    ['dress', 'Dress'],
    ['cape', 'Cape'],
    ['coat', 'Coat'],
    ['cloak', 'Cloak'],
    ['waistband', 'Waistband'],
    ['train', 'Train'],
    ['accessories', 'Accessories'],
    ['accessor', 'Accessories'],
    ['wig', 'Wig'],
    ['jumper', 'JSK'],
    ['sk', 'Skirt'],
    ['kc', 'KC'],
    ['op', 'OP'],
    ['jsk', 'JSK'],
    ['hat', 'Hat'],
    ['top', 'Top']
  ];

  var PIECE_RES = PIECE_KEYWORDS.map(function (pair) {
    return [new RegExp('\\b' + escapeRegExp(pair[0]) + '(?:s|es)?\\b'), pair[1]];
  });

  function hasOwn(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key);
  }

  function titleCase(text) {
    return String(text == null ? '' : text).replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }

  function stripColorWords(text) {
    var re = new RegExp(COLOR_RE.source, 'gi');
    return String(text == null ? '' : text)
      .replace(re, ' ')
      .replace(/[\/|,;]+/g, ' ')
      .replace(/\b(colou?r|size|length|style|type|piece|item|part|option\s*\d+)\b/ig, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function colorLabel(text) {
    var source = String(text == null ? '' : text);
    var re = new RegExp(COLOR_RE.source, 'gi');
    var found = [];
    var m;
    while ((m = re.exec(source))) {
      var label = titleCase(m[1]);
      if (found.indexOf(label) < 0) found.push(label);
      if (found.length >= 3) break;
    }
    return found.length ? found.join('/') : null;
  }

  function cleanPieceSegment(segment) {
    return String(segment == null ? '' : segment)
      .replace(/\([^()]*\)/g, ' ')
      .replace(/\b(only|set|piece|pcs?|in stock|pre[- ]?order|preorder|custom(?: order)?|choose|one size|free size|not sold separately|sold separately|optional|include[sd]?)\b/ig, ' ')
      .replace(/[^a-z0-9\s-]/ig, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function normalizePieceName(text) {
    return titleCase(stripColorWords(cleanPieceSegment(text)));
  }

  function canonicalPiece(segment) {
    var cleaned = cleanPieceSegment(segment).toLowerCase();
    if (!cleaned) return null;
    for (var i = 0; i < PIECE_RES.length; i++) {
      if (PIECE_RES[i][0].test(cleaned)) return PIECE_RES[i][1];
    }
    return null;
  }

  function looksLikeBundle(text) {
    var s = String(text == null ? '' : text);
    if (/[+&]/.test(s)) return true;
    if (/\b\d+\s*[-\s]?\s*pieces?\b/i.test(s)) return true;
    return /\bset\b/i.test(s) && !/\bnot sold separately\b/i.test(s);
  }

  function extractParenList(text) {
    var re = /\(([^()]*)\)/g;
    var m;
    while ((m = re.exec(text))) {
      if (/[+&]|\band\b/i.test(m[1])) return m[1];
    }
    return null;
  }

  function parsePieceList(text, defaultColor) {
    var raw = String(text == null ? '' : text);
    var body = looksLikeBundle(raw) ? (extractParenList(raw) || raw) : raw;
    var segments = body.split(/\s*\+\s*|\s*&\s*|\s+\band\b\s+/i);
    var out = [];
    var seen = {};
    for (var i = 0; i < segments.length; i++) {
      var segment = segments[i].trim();
      if (!segment) continue;
      var canonical = canonicalPiece(segment);
      var name = canonical || normalizePieceName(segment);
      if (!name || seen[name]) continue;
      seen[name] = true;
      out.push({
        name: name,
        canonical: !!canonical,
        color: colorLabel(segment) || defaultColor || null,
        raw: segment
      });
    }
    return out;
  }

  function betterVariant(a, b) {
    if (!!a.available !== !!b.available) return !!a.available;
    return Number(a.price) < Number(b.price);
  }

  function variantSignature(v) {
    var options = v.options || {};
    var parts = [];
    for (var key in options) {
      if (!hasOwn(options, key)) continue;
      if (/size|length/i.test(key)) continue;
      parts.push(String(options[key]));
    }
    return parts.join(' / ') || v.variantTitle || String(v.id);
  }

  function variantPieceTexts(v) {
    var options = v.options || {};
    var texts = [];
    var colorTexts = [];
    for (var key in options) {
      if (!hasOwn(options, key)) continue;
      var value = options[key] == null ? '' : String(options[key]);
      if (!value) continue;
      if (/size|length/i.test(key)) continue;
      if (/colou?r/i.test(key)) { colorTexts.push(value); continue; }
      if (/combination|status|shipping|availability/i.test(key)) continue;
      texts.push(value);
    }
    if (!texts.length) texts = colorTexts;
    if (!texts.length && v.piece) texts.push(v.piece);
    if (!texts.length && v.variantTitle) texts.push(v.variantTitle);
    return texts;
  }

  function variantPieces(v) {
    var texts = variantPieceTexts(v);
    var pieces = [];
    var bundle = false;
    for (var i = 0; i < texts.length; i++) {
      if (looksLikeBundle(texts[i])) bundle = true;
      var parsed = parsePieceList(texts[i], v.color);
      for (var j = 0; j < parsed.length; j++) {
        var duplicate = false;
        for (var k = 0; k < pieces.length; k++) {
          if (pieces[k].name === parsed[j].name) { duplicate = true; break; }
        }
        if (!duplicate) pieces.push(parsed[j]);
      }
    }
    if (pieces.length > 1) bundle = true;
    return { pieces: pieces, bundle: bundle };
  }

  function classify(optionValues) {
    var entries = entryList(optionValues);
    var sizeValue = null;
    var pieceParts = [];
    var colorTexts = [];
    for (var i = 0; i < entries.length; i++) {
      var name = String(entries[i][0] || '');
      var value = entries[i][1] == null ? '' : String(entries[i][1]);
      if (!value) continue;
      if (/size|length/i.test(name) && sizeValue == null) {
        sizeValue = value;
        continue;
      }
      if (/colou?r/i.test(name)) {
        colorTexts.push(value);
        var remainder = stripColorWords(value);
        if (remainder) pieceParts.push(remainder);
        continue;
      }
      pieceParts.push(value);
    }
    var pieceText = pieceParts.join(' ').trim();
    var colorText = colorTexts.join(' ').trim();
    var color = colorLabel(colorText) || colorLabel(pieceText) || null;
    var piece = normalizePieceName(pieceText) || normalizePieceName(colorText) || 'Item';
    return {
      piece: piece,
      size: sizeValue,
      color: color
    };
  }

  function loadAll() {
    try {
      var raw = typeof GM_getValue === 'function'
        ? GM_getValue(STORAGE_KEY, '[]')
        : (localStorage.getItem(STORAGE_KEY) || '[]');
      var list = JSON.parse(raw);
      return Array.isArray(list) ? list : [];
    } catch (e) {
      return [];
    }
  }

  function saveAll(list) {
    var raw = JSON.stringify(list);
    if (typeof GM_setValue === 'function') GM_setValue(STORAGE_KEY, raw);
    else localStorage.setItem(STORAGE_KEY, raw);
  }

  function normalizeHandleValue(handle) {
    var text = String(handle == null ? '' : handle).trim();
    if (!text) return '';
    try { text = decodeURIComponent(text); } catch (e) {}
    return text.replace(/\/+$/, '').toLowerCase();
  }

  function normalizeSource(source) {
    var text = String(source || '42lolita.com').toLowerCase().replace(/^www\./, '').replace(/^m\./, '');
    if (text === 'aliexpress.us') text = 'aliexpress.com';
    return text;
  }

  function listingKeys(record) {
    var keys = [];
    var source = normalizeSource(record.source);
    var handle = normalizeHandleValue(record.handle);
    if (handle) keys.push(source + '|' + handle);
    var pathMatch = String(record.url || '').match(/^https?:\/\/[^/]+(\/[^?#]*)/);
    if (pathMatch) keys.push(source + '|url:' + normalizeHandleValue(pathMatch[1]));
    var image = String(record.image || '').split('?')[0].replace(/^https?:/, '');
    if (image.length > 20) keys.push('image:' + image);
    if (!keys.length) keys.push(source + '|' + normalizeHandleValue(record.name));
    return keys;
  }

  function recordKey(record) {
    return listingKeys(record)[0];
  }

  function compactSnapshot(record) {
    var variants = [];
    var source = (record && record.variants) || [];
    for (var i = 0; i < source.length; i++) {
      variants.push({
        id: source[i].id != null ? source[i].id : (source[i].variantTitle || ''),
        price: Number(source[i].price) || 0,
        available: !!source[i].available
      });
    }
    return {
      savedAt: (record && record.savedAt) || '',
      currency: (record && record.currency) || '',
      variants: variants
    };
  }

  function pushHistory(history, snapshot) {
    var list = Array.isArray(history) ? history.slice() : [];
    var day = String(snapshot.savedAt || '').slice(0, 10);
    var replaced = false;
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].savedAt || '').slice(0, 10) === day) {
        list[i] = snapshot;
        replaced = true;
        break;
      }
    }
    if (!replaced) list.push(snapshot);
    list.sort(function (a, b) {
      var aDate = String(a.savedAt || '');
      var bDate = String(b.savedAt || '');
      if (aDate === bDate) return 0;
      return aDate < bDate ? -1 : 1;
    });
    if (list.length > 180) list = list.slice(list.length - 180);
    return list;
  }

  function mergeHistoryFrom(base, other) {
    var history = Array.isArray(base.history) ? base.history.slice() : [];
    var otherHistory = Array.isArray(other.history) ? other.history : [];
    for (var i = 0; i < otherHistory.length; i++) history = pushHistory(history, otherHistory[i]);
    history = pushHistory(history, compactSnapshot(other));
    base.history = history;
    return base;
  }

  function dedupeList(products) {
    var groups = {};
    var out = [];
    for (var i = 0; i < products.length; i++) {
      var record = products[i];
      var keys = listingKeys(record);
      var target = -1;
      for (var k = 0; k < keys.length; k++) {
        if (groups[keys[k]] !== undefined) {
          target = groups[keys[k]];
          break;
        }
      }
      if (target < 0) {
        out.push(record);
        target = out.length - 1;
      } else {
        var existing = out[target];
        var newer = String(record.savedAt || '') >= String(existing.savedAt || '') ? record : existing;
        var older = newer === record ? existing : record;
        var mergedKeys = listingKeys(existing).concat(listingKeys(record));
        out[target] = mergeHistoryFrom(newer, older);
        for (var mk = 0; mk < mergedKeys.length; mk++) groups[mergedKeys[mk]] = target;
      }
      var recordKeys = listingKeys(out[target]);
      for (var rk = 0; rk < recordKeys.length; rk++) groups[recordKeys[rk]] = target;
    }
    return out;
  }

  function dedupeRecords() {
    var all = loadAll();
    var out = dedupeList(all);
    if (out.length === all.length) return 0;
    saveAll(out);
    return all.length - out.length;
  }

  function recordsMatch(a, b) {
    var aKeys = listingKeys(a);
    var bKeys = listingKeys(b);
    for (var i = 0; i < aKeys.length; i++) {
      if (bKeys.indexOf(aKeys[i]) >= 0) return true;
    }
    return false;
  }

  function upsertRecord(record) {
    var all = loadAll();
    for (var i = 0; i < all.length; i++) {
      if (recordsMatch(all[i], record)) {
        record.history = pushHistory(all[i].history, compactSnapshot(all[i]));
        all[i] = record;
        saveAll(all);
        return i;
      }
    }
    all.push(record);
    saveAll(all);
    return all.length - 1;
  }

  function recordItemKey(record) {
    if (!record) return '';
    return (record.source || '42lolita.com') + '|' + (record.handle || record.name || '');
  }

  function qualifyKey(key) {
    var text = String(key == null ? '' : key);
    return text.indexOf('|') >= 0 ? text : '42lolita.com|' + text;
  }

  function loadPriority() {
    try {
      var raw = typeof GM_getValue === 'function'
        ? GM_getValue(PRIORITY_KEY, '{}')
        : (localStorage.getItem(PRIORITY_KEY) || '{}');
      var map = JSON.parse(raw);
      return map && typeof map === 'object' ? map : {};
    } catch (e) {
      return {};
    }
  }

  function savePriority(map) {
    var raw = JSON.stringify(map);
    if (typeof GM_setValue === 'function') GM_setValue(PRIORITY_KEY, raw);
    else localStorage.setItem(PRIORITY_KEY, raw);
  }

  function priorityScore(record) {
    var key = recordItemKey(record);
    if (!key) return 0;
    var map = loadPriority();
    return Number(map[key]) || 0;
  }

  function likeItem(record) {
    var key = recordItemKey(record);
    if (!key) return 0;
    var map = loadPriority();
    var max = 0;
    for (var k in map) {
      if (hasOwn(map, k) && Number(map[k]) > max) max = Number(map[k]);
    }
    var stamp = Math.max(Date.now(), max + 1);
    map[key] = stamp;
    savePriority(map);
    return stamp;
  }

  function isLiked(record) {
    return priorityScore(record) > 0;
  }

  function loadUnavailable() {
    try {
      var raw = typeof GM_getValue === 'function'
        ? GM_getValue(UNAVAILABLE_KEY, '{}')
        : (localStorage.getItem(UNAVAILABLE_KEY) || '{}');
      var map = JSON.parse(raw);
      return map && typeof map === 'object' ? map : {};
    } catch (e) {
      return {};
    }
  }

  function saveUnavailable(map) {
    var raw = JSON.stringify(map);
    if (typeof GM_setValue === 'function') GM_setValue(UNAVAILABLE_KEY, raw);
    else localStorage.setItem(UNAVAILABLE_KEY, raw);
  }

  function loadUi() {
    try {
      var raw = typeof GM_getValue === 'function'
        ? GM_getValue(UI_KEY, '{}')
        : (localStorage.getItem(UI_KEY) || '{}');
      var map = JSON.parse(raw);
      return map && typeof map === 'object' ? map : {};
    } catch (e) {
      return {};
    }
  }

  function saveUi(map) {
    var raw = JSON.stringify(map);
    if (typeof GM_setValue === 'function') GM_setValue(UI_KEY, raw);
    else localStorage.setItem(UI_KEY, raw);
  }

  function loadCollections() {
    try {
      var raw = storageGet(COLLECTIONS_KEY) || '[]';
      var list = JSON.parse(raw);
      return Array.isArray(list) ? list : [];
    } catch (e) {
      return [];
    }
  }

  function saveCollections(list) {
    storageSet(COLLECTIONS_KEY, JSON.stringify(list));
  }

  function findCollection(id) {
    var list = loadCollections();
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i];
    }
    return null;
  }

  function createCollection(name) {
    var clean = String(name == null ? '' : name).trim().slice(0, 60);
    if (!clean) return null;
    var list = loadCollections();
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name || '').toLowerCase() === clean.toLowerCase()) return list[i];
    }
    var collection = {
      id: 'set-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      name: clean,
      items: []
    };
    list.push(collection);
    saveCollections(list);
    return collection;
  }

  function deleteCollection(id) {
    var list = loadCollections();
    var kept = [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].id !== id) kept.push(list[i]);
    }
    saveCollections(kept);
    if (getDefaultSetId() === id) setDefaultSetId(null);
  }

  function addCollectionItem(id, itemKey) {
    if (!id || !itemKey) return false;
    var list = loadCollections();
    var collection = null;
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) collection = list[i];
    }
    if (!collection) return false;
    if (!Array.isArray(collection.items)) collection.items = [];
    if (collection.items.indexOf(itemKey) >= 0) return false;
    collection.items.push(itemKey);
    saveCollections(list);
    return true;
  }

  function getDefaultSetId() {
    var ui = loadUi();
    return ui.addToSet || null;
  }

  function setDefaultSetId(id) {
    var ui = loadUi();
    ui.addToSet = id || null;
    saveUi(ui);
  }

  function getSortBy() {
    var ui = loadUi();
    return ui.sortBy === 'priority' ? 'priority' : 'recent';
  }

  function setSortBy(value) {
    var ui = loadUi();
    ui.sortBy = value === 'priority' ? 'priority' : 'recent';
    saveUi(ui);
  }

  function toggleCollectionItem(id, itemKey) {
    if (!id || !itemKey) return false;
    var list = loadCollections();
    var collection = null;
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) collection = list[i];
    }
    if (!collection) return false;
    if (!Array.isArray(collection.items)) collection.items = [];
    var index = collection.items.indexOf(itemKey);
    if (index >= 0) {
      collection.items.splice(index, 1);
      saveCollections(list);
      return false;
    }
    collection.items.push(itemKey);
    saveCollections(list);
    return true;
  }

  function collectionsForItem(itemKey) {
    var list = loadCollections();
    var out = [];
    for (var i = 0; i < list.length; i++) {
      if (list[i] && Array.isArray(list[i].items) && list[i].items.indexOf(itemKey) >= 0) out.push(list[i]);
    }
    return out;
  }

  function collectionRecord(collection) {
    if (!collection) return null;
    var byKey = {};
    var records = latestSnapshots(loadAll());
    for (var i = 0; i < records.length; i++) byKey[recordItemKey(records[i])] = records[i];
    var items = Array.isArray(collection.items) ? collection.items : [];
    var variants = [];
    var first = null;
    for (var j = 0; j < items.length; j++) {
      var record = byKey[items[j]];
      if (!record) continue;
      if (!first) first = record;
      var recordVariants = record.variants || [];
      for (var k = 0; k < recordVariants.length; k++) {
        var variant = JSON.parse(JSON.stringify(recordVariants[k]));
        variant.variantTitle = record.name + ' \u2014 ' + (variant.variantTitle || variant.piece || '');
        variants.push(variant);
      }
    }
    if (!first) return null;
    return {
      name: 'Set: ' + collection.name,
      handle: collection.id,
      source: 'shoplita.set',
      url: first.url,
      image: first.image || null,
      currency: first.currency || '',
      savedAt: new Date().toISOString(),
      variants: variants
    };
  }

  function loadOutfits() {
    try {
      var raw = storageGet(OUTFITS_KEY) || '[]';
      var list = JSON.parse(raw);
      return Array.isArray(list) ? list : [];
    } catch (e) {
      return [];
    }
  }

  function saveOutfits(list) {
    storageSet(OUTFITS_KEY, JSON.stringify(list));
  }

  function createOutfit(name, pieces, currency) {
    if (!Array.isArray(pieces) || !pieces.length) return null;
    var clean = String(name == null ? '' : name).trim().slice(0, 60) ||
      ('Outfit ' + new Date().toISOString().slice(0, 10));
    var total = 0;
    for (var i = 0; i < pieces.length; i++) total += Number(pieces[i].price) || 0;
    var outfit = {
      id: 'fit-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      name: clean,
      createdAt: new Date().toISOString(),
      currency: currency || '',
      total: Math.round(total * 100) / 100,
      pieces: pieces
    };
    var list = loadOutfits();
    list.push(outfit);
    saveOutfits(list);
    return outfit;
  }

  function deleteOutfit(id) {
    var list = loadOutfits();
    var kept = [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].id !== id) kept.push(list[i]);
    }
    saveOutfits(kept);
  }

  function outfitRecord(outfit) {
    if (!outfit || !Array.isArray(outfit.pieces) || !outfit.pieces.length) return null;
    var variants = [];
    for (var i = 0; i < outfit.pieces.length; i++) {
      var piece = outfit.pieces[i];
      var options = { 'Piece': piece.name };
      if (piece.color) options['Color'] = piece.color;
      variants.push({
        id: outfit.id + '-' + i,
        variantTitle: piece.name + (piece.color ? ' / ' + piece.color : ''),
        piece: piece.name,
        color: piece.color || null,
        size: null,
        price: Number(piece.price) || 0,
        compareAtPrice: null,
        available: piece.available !== false,
        sku: null,
        options: options,
        url: piece.itemUrl || null
      });
    }
    return {
      name: 'Outfit: ' + outfit.name,
      handle: outfit.id,
      source: 'shoplita.outfit',
      url: null,
      image: null,
      currency: outfit.currency || '',
      savedAt: outfit.createdAt || new Date().toISOString(),
      variants: variants
    };
  }

  function normalizeSources() {
    var changed = false;
    var all = loadAll();
    for (var i = 0; i < all.length; i++) {
      if (!all[i].source) {
        all[i].source = '42lolita.com';
        changed = true;
      }
    }
    if (changed) saveAll(all);
    dedupeRecords();
    var maps = [[loadPriority, savePriority], [loadUnavailable, saveUnavailable]];
    for (var m = 0; m < maps.length; m++) {
      var map = maps[m][0]();
      var dirty = false;
      var migrated = {};
      for (var key in map) {
        if (!hasOwn(map, key)) continue;
        var newKey = qualifyKey(key);
        if (newKey !== key) dirty = true;
        migrated[newKey] = map[key];
      }
      if (dirty) maps[m][1](migrated);
    }
    var priority = loadPriority();
    var legacyPriority = [];
    for (var pk in priority) {
      if (!hasOwn(priority, pk)) continue;
      var priorityValue = Number(priority[pk]) || 0;
      if (priorityValue > 0 && priorityValue < 1000000000000) legacyPriority.push([pk, priorityValue]);
    }
    if (legacyPriority.length) {
      legacyPriority.sort(function (a, b) { return a[1] - b[1]; });
      var priorityBase = Date.now();
      for (var lp = 0; lp < legacyPriority.length; lp++) {
        priority[legacyPriority[lp][0]] = priorityBase - (legacyPriority.length - lp) * 1000;
      }
      savePriority(priority);
    }
    var keys = loadCompareKeys();
    var keyDirty = false;
    if (keys.a && keys.a.indexOf('|') < 0) { keys.a = qualifyKey(keys.a); keyDirty = true; }
    if (keys.b && keys.b.indexOf('|') < 0) { keys.b = qualifyKey(keys.b); keyDirty = true; }
    if (keyDirty) saveCompareKeys(keys);
  }

  function storageGet(key) {
    try {
      if (typeof GM_getValue === 'function') return GM_getValue(key, null);
      return typeof localStorage !== 'undefined' ? localStorage.getItem(key) : null;
    } catch (e) {
      return null;
    }
  }

  function storageSet(key, value) {
    try {
      if (typeof GM_setValue === 'function') GM_setValue(key, value);
      else if (typeof localStorage !== 'undefined') localStorage.setItem(key, value);
    } catch (e) {}
  }

  function migrateLegacyKeys() {
    var legacy = [
      ['savedInfo.v1', STORAGE_KEY],
      ['priority.v1', PRIORITY_KEY],
      ['unavailable.v1', UNAVAILABLE_KEY],
      ['compare.v1', COMPARE_KEY],
      ['ui.v1', UI_KEY]
    ];
    for (var i = 0; i < legacy.length; i++) {
      var oldValue = storageGet(legacy[i][0]);
      var newValue = storageGet(legacy[i][1]);
      if (oldValue != null && newValue == null) storageSet(legacy[i][1], oldValue);
    }
  }

  function isMarkedUnavailable(record) {
    var key = recordItemKey(record);
    if (!key) return false;
    return !!loadUnavailable()[key];
  }

  function toggleUnavailable(record) {
    var key = recordItemKey(record);
    if (!key) return false;
    var map = loadUnavailable();
    if (map[key]) delete map[key];
    else map[key] = true;
    saveUnavailable(map);
    return !!map[key];
  }

  function removeItemGroup(itemKey) {
    var all = loadAll();
    var kept = [];
    for (var i = 0; i < all.length; i++) {
      if (recordItemKey(all[i]) !== itemKey) kept.push(all[i]);
    }
    saveAll(kept);
    var priority = loadPriority();
    if (priority[itemKey] !== undefined) {
      delete priority[itemKey];
      savePriority(priority);
    }
    var unavailable = loadUnavailable();
    if (unavailable[itemKey] !== undefined) {
      delete unavailable[itemKey];
      saveUnavailable(unavailable);
    }
    var collections = loadCollections();
    var collectionsChanged = false;
    for (var c = 0; c < collections.length; c++) {
      var items = collections[c].items;
      if (!Array.isArray(items)) continue;
      var membership = items.indexOf(itemKey);
      if (membership >= 0) {
        items.splice(membership, 1);
        collectionsChanged = true;
      }
    }
    if (collectionsChanged) saveCollections(collections);
    return all.length - kept.length;
  }

  function sanitizeRecord(raw) {
    if (!raw || typeof raw !== 'object' || !Array.isArray(raw.variants) || !raw.variants.length) return null;
    var record = JSON.parse(JSON.stringify({
      name: raw.name,
      type: raw.type,
      brand: raw.brand,
      productCode: raw.productCode,
      currency: raw.currency,
      source: raw.source,
      handle: raw.handle,
      url: raw.url,
      image: raw.image,
      images: raw.images,
      savedAt: raw.savedAt,
      variants: raw.variants
    }));
    if (!record.name) record.name = record.handle || 'Imported product';
    if (!record.savedAt) record.savedAt = new Date().toISOString();
    if (record.currency == null) record.currency = '';
    var variants = [];
    for (var i = 0; i < record.variants.length; i++) {
      var v = record.variants[i];
      if (!v || typeof v !== 'object' || v.price == null || isNaN(Number(v.price))) continue;
      variants.push(v);
    }
    if (!variants.length) return null;
    record.variants = variants;
    return record;
  }

  function recordsFromImport(data) {
    if (Array.isArray(data)) return data;
    if (data && Array.isArray(data.products)) return data.products;
    if (data && Array.isArray(data.variants)) return [data];
    return null;
  }

  function mergeImport(text) {
    var data;
    try {
      data = JSON.parse(text);
    } catch (e) {
      return { error: 'not valid JSON' };
    }
    var incoming = recordsFromImport(data);
    if (!incoming) {
      return { error: 'no product records found (use a saved JSON export)' };
    }
    var all = loadAll();
    var index = {};
    function indexRecord(record, at) {
      var keys = listingKeys(record);
      for (var k = 0; k < keys.length; k++) index[keys[k]] = at;
    }
    for (var i = 0; i < all.length; i++) indexRecord(all[i], i);
    var result = { added: 0, updated: 0, skipped: 0, total: 0 };
    for (var j = 0; j < incoming.length; j++) {
      var record = sanitizeRecord(incoming[j]);
      if (!record) { result.skipped++; continue; }
      var keys = listingKeys(record);
      var matchIndex = -1;
      for (var mk = 0; mk < keys.length; mk++) {
        if (index[keys[mk]] !== undefined) {
          matchIndex = index[keys[mk]];
          break;
        }
      }
      if (matchIndex >= 0) {
        var existing = all[matchIndex];
        if (String(record.savedAt || '') >= String(existing.savedAt || '')) {
          var mergedKeys = listingKeys(existing).concat(keys);
          all[matchIndex] = record;
          for (var rk = 0; rk < mergedKeys.length; rk++) index[mergedKeys[rk]] = matchIndex;
          result.updated++;
        } else {
          result.skipped++;
        }
      } else {
        all.push(record);
        indexRecord(record, all.length - 1);
        result.added++;
      }
    }
    saveAll(all);
    if (data && data.priority && typeof data.priority === 'object') {
      var priority = loadPriority();
      for (var pk in data.priority) {
        if (!hasOwn(data.priority, pk)) continue;
        var qualified = qualifyKey(pk);
        var score = Number(data.priority[pk]) || 0;
        if (score > (Number(priority[qualified]) || 0)) priority[qualified] = score;
      }
      savePriority(priority);
    }
    if (data && data.unavailable && typeof data.unavailable === 'object') {
      var unavailable = loadUnavailable();
      for (var uk in data.unavailable) {
        if (hasOwn(data.unavailable, uk) && data.unavailable[uk]) unavailable[qualifyKey(uk)] = true;
      }
      saveUnavailable(unavailable);
    }
    if (data && Array.isArray(data.collections)) {
      var collections = loadCollections();
      for (var ci = 0; ci < data.collections.length; ci++) {
        var incomingCollection = data.collections[ci];
        if (!incomingCollection || !incomingCollection.name) continue;
        var target = null;
        for (var cj = 0; cj < collections.length; cj++) {
          if (String(collections[cj].name || '').toLowerCase() === String(incomingCollection.name).toLowerCase()) {
            target = collections[cj];
            break;
          }
        }
        if (!target) {
          target = {
            id: incomingCollection.id || ('set-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6)),
            name: incomingCollection.name,
            items: []
          };
          collections.push(target);
        }
        if (!Array.isArray(target.items)) target.items = [];
        var incomingItems = Array.isArray(incomingCollection.items) ? incomingCollection.items : [];
        for (var ii = 0; ii < incomingItems.length; ii++) {
          if (target.items.indexOf(incomingItems[ii]) < 0) target.items.push(incomingItems[ii]);
        }
      }
      saveCollections(collections);
    }
    if (data && Array.isArray(data.outfits)) {
      var outfits = loadOutfits();
      for (var oi = 0; oi < data.outfits.length; oi++) {
        var incomingOutfit = data.outfits[oi];
        if (!incomingOutfit || !incomingOutfit.name) continue;
        var duplicate = false;
        for (var oj = 0; oj < outfits.length; oj++) {
          if (String(outfits[oj].name || '').toLowerCase() === String(incomingOutfit.name).toLowerCase()) {
            duplicate = true;
            break;
          }
        }
        if (!duplicate) outfits.push(incomingOutfit);
      }
      saveOutfits(outfits);
    }
    result.total = all.length;
    return result;
  }

  function pickImportFile(onDone) {
    var input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json,application/json';
    input.style.display = 'none';
    document.body.appendChild(input);
    input.addEventListener('change', function () {
      var file = input.files && input.files[0];
      if (input.parentNode) input.parentNode.removeChild(input);
      if (!file) return;
      var reader = new FileReader();
      reader.onload = function () { onDone(String(reader.result || '')); };
      reader.onerror = function () { toast('Could not read import file', true); };
      reader.readAsText(file);
    });
    input.click();
  }

  function copyFallback(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try {
      ok = document.execCommand('copy');
    } catch (e) {}
    if (ta.parentNode) ta.parentNode.removeChild(ta);
    return ok;
  }

  function copyText(text) {
    if (typeof GM_setClipboard === 'function') {
      try {
        GM_setClipboard(text);
        return Promise.resolve(true);
      } catch (e) {}
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).then(
        function () { return true; },
        function () { return copyFallback(text); }
      );
    }
    return Promise.resolve(copyFallback(text));
  }

  function download(filename, text, mime) {
    try {
      var blob = new Blob([text], { type: mime || 'application/json' });
      var url = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      if (a.parentNode) a.parentNode.removeChild(a);
      setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
      return true;
    } catch (e) {
      return false;
    }
  }

  function fetchJson(url) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, true);
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4) return;
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            resolve(JSON.parse(xhr.responseText));
          } catch (e) {
            reject(e);
          }
        } else {
          reject(new Error('HTTP ' + xhr.status));
        }
      };
      xhr.onerror = function () { reject(new Error('network error')); };
      xhr.send();
    });
  }

  function detectCurrency() {
    var scripts = document.querySelectorAll('script[type="application/ld+json"]');
    for (var i = 0; i < scripts.length; i++) {
      var m = (scripts[i].textContent || '').match(/"priceCurrency"\s*:\s*"([A-Z]{3})"/);
      if (m) return m[1];
    }
    var meta = document.querySelector('meta[property="product:price:currency"], meta[itemprop="priceCurrency"]');
    return (meta && meta.content) || 'USD';
  }

  function normalize(product, handle, currency) {
    var optionNames = [];
    var opts = product.options || [];
    for (var i = 0; i < opts.length; i++) {
      optionNames.push(typeof opts[i] === 'string' ? opts[i] : opts[i].name);
    }
    var variants = [];
    var pvs = product.variants || [];
    for (var j = 0; j < pvs.length; j++) {
      var v = pvs[j];
      var values = [v.option1, v.option2, v.option3].filter(function (x) {
        return x !== null && x !== undefined && x !== '';
      });
      var optionValues = {};
      for (var k = 0; k < values.length; k++) {
        optionValues[optionNames[k] || 'Option ' + (k + 1)] = values[k];
      }
      var info = classify(optionValues);
      variants.push({
        id: v.id,
        variantTitle: v.title,
        piece: info.piece,
        color: info.color,
        size: info.size,
        price: centsToNumber(v.price),
        compareAtPrice: v.compare_at_price && Number(v.compare_at_price) > 0
          ? centsToNumber(v.compare_at_price)
          : null,
        available: !!v.available,
        sku: v.sku || null,
        options: optionValues,
        url: location.origin + location.pathname + '?variant=' + v.id
      });
    }
    var images = collectImages(product.images || product.image || product.featured_image);
    var primaryImage = firstImage(product.featured_image) || (images.length ? images[0] : null);
    if (primaryImage && images.indexOf(primaryImage) < 0) images.unshift(primaryImage);
    return {
      name: product.title,
      type: product.type || null,
      brand: product.vendor || null,
      productCode: productCodeFrom(product.description),
      image: primaryImage,
      images: images.slice(0, 6),
      currency: currency,
      source: currentSource(),
      handle: handle,
      url: location.origin + location.pathname,
      savedAt: new Date().toISOString(),
      variants: variants
    };
  }

  function guessOptionName(value, index) {
    if (SIZE_RE.test(value) || /length/i.test(value)) return 'Size';
    if (detectColor(value)) return 'Color';
    if (index === 0) return 'Color';
    return 'Option ' + (index + 1);
  }

  function variantParts(fullName, productName) {
    var prefix = (productName || '') + ' - ';
    var title = fullName && fullName.indexOf(prefix) === 0 ? fullName.slice(prefix.length) : (fullName || '');
    return title.split(' / ');
  }

  function idFromUrl(u) {
    var m = String(u || '').match(/variant=(\d+)/);
    return m ? Number(m[1]) : (u || null);
  }

  function fromJsonLd() {
    var scripts = document.querySelectorAll('script[type="application/ld+json"]');
    var group = null;
    for (var i = 0; i < scripts.length; i++) {
      var data;
      try {
        data = JSON.parse(scripts[i].textContent);
      } catch (e) {
        continue;
      }
      if (data && data['@type'] === 'ProductGroup' && data.hasVariant && data.hasVariant.length) {
        group = data;
        break;
      }
    }
    if (!group) return null;

    var productName = group.name || document.title;
    var variants = [];
    var optionNames = null;
    for (var j = 0; j < group.hasVariant.length; j++) {
      var hv = group.hasVariant[j] || {};
      var parts = variantParts(hv.name, productName);
      var offer = hv.offers || {};
      if (!optionNames) {
        optionNames = [];
        for (var n = 0; n < parts.length; n++) optionNames.push(guessOptionName(parts[n], n));
      }
      variants.push({
        id: idFromUrl(offer.url || hv['@id']),
        title: parts.join(' / '),
        option1: parts[0] || null,
        option2: parts[1] || null,
        option3: parts[2] || null,
        price: Math.round(parseFloat(offer.price || 0) * 100),
        compare_at_price: null,
        available: /InStock/i.test(offer.availability || ''),
        sku: hv.sku || null
      });
    }
    return {
      title: productName,
      type: group.category || null,
      vendor: (group.brand && group.brand.name) || null,
      description: group.description || '',
      image: firstImage(group.image),
      options: optionNames || [],
      variants: variants
    };
  }

  function currentHandle() {
    var m = location.pathname.match(/\/products\/([^/?#]+)/);
    return m ? m[1] : null;
  }

  function currentPageId() {
    var handle = currentHandle();
    if (handle) return handle;
    var path = String(location.pathname || '');
    var parts = path.split('/').filter(function (part) { return !!part; });
    var last = parts.length ? parts[parts.length - 1] : '';
    return last.replace(/\.html?$/i, '') || null;
  }

  function currentSource() {
    return String(location.hostname || '').replace(/^www\./, '') || '42lolita.com';
  }

  function recordOrigin(record) {
    var match = String((record && record.url) || '').match(/^https?:\/\/[^/]+/);
    return match ? match[0] : location.origin;
  }

  function findLatestByHandle(handle) {
    if (!handle) return null;
    var all = loadAll();
    var latest = null;
    for (var i = 0; i < all.length; i++) {
      if (all[i].handle !== handle || (all[i].source || '42lolita.com') !== currentSource()) continue;
      if (!latest || String(all[i].savedAt || '') > String(latest.savedAt || '')) latest = all[i];
    }
    return latest;
  }

  var ADAPTERS = [];

  function registerAdapter(adapter) {
    ADAPTERS.push(adapter);
  }

  function adapterFor(url) {
    for (var i = 0; i < ADAPTERS.length; i++) {
      if (ADAPTERS[i].matches(url)) return ADAPTERS[i];
    }
    return null;
  }

  registerAdapter({
    id: 'shopify',
    label: '42Lolita and other Shopify stores',
    matches: function () {
      return /\/products\/[^/?#]+/.test(location.pathname);
    },
    collect: function () {
      var handle = currentHandle();
      if (!handle) return Promise.reject(new Error('not a product page'));
      var url = location.origin + '/products/' + encodeURIComponent(handle) + '.js';
      return fetchJson(url).catch(function () { return null; }).then(function (product) {
        if (!product || !product.variants || !product.variants.length) product = fromJsonLd();
        if (!product || !product.variants || !product.variants.length) {
          throw new Error('could not read product data');
        }
        return normalize(product, handle, detectCurrency());
      });
    }
  });

  function domText(selector) {
    var el = document.querySelector(selector);
    return el && el.textContent ? el.textContent.trim() : '';
  }

  function metaContent(selector) {
    var el = document.querySelector(selector);
    return el ? (el.getAttribute('content') || '') : '';
  }

  function parsePriceNumber(text) {
    var match = String(text == null ? '' : text).replace(/\s/g, '').match(/(\d[\d.,]*)/);
    if (!match) return null;
    var value = parseFloat(match[1].replace(/,/g, ''));
    return isNaN(value) ? null : value;
  }

  function domPriceNumber() {
    var candidates = [
      metaContent('meta[itemprop="price"]'),
      metaContent('meta[property="product:price:amount"]'),
      metaContent('meta[property="og:price:amount"]')
    ];
    for (var i = 0; i < candidates.length; i++) {
      var meta = parsePriceNumber(candidates[i]);
      if (meta != null) return meta;
    }
    var priceEl = document.querySelector('[itemprop="price"], .product-price-lg, .product-price, #price, .price, [class*="price-default--current"], [class*="price--current"]');
    if (priceEl) {
      var elementPrice = parsePriceNumber(priceEl.textContent);
      if (elementPrice != null) return elementPrice;
    }
    var body = String(document.body ? document.body.textContent : '');
    var match = body.match(/(?:US\$|\$|€|£|¥)\s?(\d[\d.,]*)/);
    return match ? parsePriceNumber(match[1]) : null;
  }

  function domSoldOut() {
    var markers = ['[class*="soldOut"]', '[class*="sold-out"]', '[class*="outOfStock"]', '[class*="out-of-stock"]'];
    for (var i = 0; i < markers.length; i++) {
      var el = document.querySelector(markers[i]);
      if (el && (el.offsetParent === undefined || el.offsetParent !== null)) return true;
    }
    var body = document.body;
    if (!body) return false;
    var text = typeof body.innerText === 'string' ? body.innerText : String(body.textContent || '');
    return /sold ?out|out of stock/i.test(text);
  }

  function aliexpressAvailability(quantity) {
    if (quantity == null || isNaN(quantity) || quantity < 0) return true;
    return quantity > 0;
  }

  function collectGenericDom() {
    var name = metaContent('meta[property="og:title"]') || domText('h1') || document.title || 'Unnamed product';
    var price = domPriceNumber();
    if (price == null) return Promise.reject(new Error('could not read price on this page'));
    var currency = detectCurrency();
    var image = metaContent('meta[property="og:image"]') || null;
    var description = metaContent('meta[name="description"]') || '';
    var soldOut = domSoldOut();
    var variants = [];
    var seen = {};
    var nodes = document.querySelectorAll('select option, button, a, span, li');
    for (var i = 0; i < nodes.length && variants.length < 60; i++) {
      var text = String(nodes[i].textContent || '').trim();
      if (!text || text.length > 24 || !SIZE_RE.test(text) || seen[text]) continue;
      seen[text] = true;
      variants.push({
        id: text,
        title: text,
        option1: text,
        option2: null,
        option3: null,
        price: Math.round(price * 100),
        compare_at_price: null,
        available: !soldOut,
        sku: null
      });
    }
    if (!variants.length) {
      variants.push({
        id: 'base',
        title: name,
        option1: null,
        option2: null,
        option3: null,
        price: Math.round(price * 100),
        compare_at_price: null,
        available: !soldOut,
        sku: null
      });
    }
    return Promise.resolve(normalize({
      title: name,
      type: null,
      vendor: null,
      description: description,
      image: image,
      options: [],
      variants: variants
    }, currentPageId(), currency));
  }

  function collectDevilinspired() {
    var name = domText('#product-name') || metaContent('meta[property="og:title"]') || document.title;
    var price = domPriceNumber();
    if (price == null) return Promise.reject(new Error('could not read price on this page'));
    var currency = detectCurrency();
    var image = metaContent('meta[property="og:image"]') || null;
    var skuMap = null;
    try { skuMap = window.skuMap || null; } catch (e) {}
    if (!skuMap) {
      var scripts = document.querySelectorAll('script');
      for (var s = 0; s < scripts.length; s++) {
        var match = String(scripts[s].textContent || '').match(/var\s+skuMap\s*=\s*(\{[\s\S]*?\});/);
        if (!match) continue;
        try { skuMap = JSON.parse(match[1]); } catch (e2) {}
        break;
      }
    }
    var soldOut = domSoldOut();
    var variants = [];
    if (skuMap) {
      for (var key in skuMap) {
        if (!hasOwn(skuMap, key)) continue;
        var entry = skuMap[key] || {};
        var label = entry.name || '';
        if (!label) continue;
        var delta = parseFloat(entry.price || '0') || 0;
        if (entry.price_prefix === '-') delta = -delta;
        var quantity = Number(entry.quantity);
        variants.push({
          id: entry.product_option_value_id || key,
          title: label,
          option1: label,
          option2: null,
          option3: null,
          price: Math.round((price + delta) * 100),
          compare_at_price: null,
          available: isNaN(quantity) ? !soldOut : quantity !== 0,
          sku: null
        });
      }
    }
    if (!variants.length) {
      variants.push({
        id: 'base',
        title: name,
        option1: null,
        option2: null,
        option3: null,
        price: Math.round(price * 100),
        compare_at_price: null,
        available: !soldOut,
        sku: null
      });
    }
    return Promise.resolve(normalize({
      title: name,
      type: null,
      vendor: null,
      description: '',
      image: image,
      options: [],
      variants: variants
    }, currentPageId(), currency));
  }

  registerAdapter({
    id: 'devilinspired',
    label: 'Devilinspired',
    matches: function () {
      return /(^|\.)devilinspired\.com$/.test(location.hostname || '') && /\.html?$/i.test(location.pathname || '');
    },
    collect: collectDevilinspired
  });

  registerAdapter({
    id: 'my-lolita-dress',
    label: 'My-Lolita-Dress',
    matches: function () {
      return /(^|\.)my-lolita-dress\.com$/.test(location.hostname || '') && /-p\d+\.html?$/i.test(location.pathname || '');
    },
    collect: collectGenericDom
  });

  function findEmbeddedJson(names) {
    for (var n = 0; n < names.length; n++) {
      try {
        var global = window[names[n]];
        if (global && typeof global === 'object') return global;
      } catch (e) {}
    }
    var scripts = document.querySelectorAll('script');
    for (var i = 0; i < scripts.length; i++) {
      var text = String(scripts[i].textContent || '');
      if (!text) continue;
      for (var j = 0; j < names.length; j++) {
        var index = text.indexOf('window.' + names[j]);
        if (index < 0) continue;
        var start = text.indexOf('{', index);
        if (start < 0) continue;
        var depth = 0;
        for (var k = start; k < text.length; k++) {
          if (text.charAt(k) === '{') depth++;
          else if (text.charAt(k) === '}') {
            depth--;
            if (depth === 0) {
              try { return JSON.parse(text.slice(start, k + 1)); } catch (e2) {}
              break;
            }
          }
        }
      }
    }
    return null;
  }

  function aliexpressData(raw) {
    return raw && raw.data ? raw.data : (raw || {});
  }

  function aliexpressSkuBase(data) {
    var skuBase = (data.skuModule && data.skuModule.skuBase) || data.skuBase || null;
    if (!skuBase) return { props: [], skus: [] };
    return {
      props: Array.isArray(skuBase.props) ? skuBase.props : [],
      skus: Array.isArray(skuBase.skus) ? skuBase.skus : []
    };
  }

  function aliexpressVariantOptions(skuAttr, props) {
    var byVid = {};
    for (var p = 0; p < props.length; p++) {
      var values = Array.isArray(props[p].values) ? props[p].values : [];
      for (var v = 0; v < values.length; v++) {
        byVid[String(values[v].vid)] = {
          name: props[p].name || ('Option ' + (p + 1)),
          value: values[v].name || String(values[v].vid)
        };
      }
    }
    var segments = String(skuAttr || '').split(';');
    var out = [];
    for (var s = 0; s < segments.length; s++) {
      var segment = segments[s].trim();
      if (!segment) continue;
      var hash = segment.indexOf('#');
      var valueName = hash >= 0 ? segment.slice(hash + 1) : '';
      var head = hash >= 0 ? segment.slice(0, hash) : segment;
      var vid = head.indexOf(':') >= 0 ? head.split(':')[1] : head;
      var mapped = byVid[String(vid)];
      if (mapped) out.push(mapped);
      else if (valueName) out.push({ name: 'Option', value: valueName });
    }
    return out;
  }

  function aliexpressDomProperties() {
    var props = [];
    var rows = document.querySelectorAll('[class*="sku-item--property"]');
    for (var i = 0; i < rows.length && props.length < 3; i++) {
      var row = rows[i];
      var titleEl = row.querySelector ? row.querySelector('[class*="sku-item--title"]') : null;
      var title = titleEl ? String(titleEl.textContent || '').replace(/\s+/g, ' ').trim() : '';
      var nameMatch = title.match(/^([^:：]+)[:：]/) || title.match(/^([A-Za-z][A-Za-z ]*)/);
      var propName = nameMatch ? nameMatch[1].replace(/\(.*?\)/g, '').trim() : ('Option ' + (i + 1));
      var selected = row.querySelector ? row.querySelector('[class*="sku-item--selected"]') : null;
      var selectedValue = '';
      if (selected) {
        if (selected.getAttribute && selected.getAttribute('title')) selectedValue = selected.getAttribute('title');
        if (!selectedValue) selectedValue = String(selected.textContent || '').trim();
        if (!selectedValue && selected.querySelector) {
          var selectedImg = selected.querySelector('img');
          if (selectedImg && selectedImg.getAttribute) selectedValue = selectedImg.getAttribute('alt') || '';
        }
      }
      var values = [];
      var valueEls = row.querySelectorAll ? row.querySelectorAll('[data-sku-col]') : [];
      for (var v = 0; v < valueEls.length; v++) {
        var el = valueEls[v];
        var text = '';
        if (el.getAttribute && el.getAttribute('title')) text = el.getAttribute('title');
        if (!text) text = String(el.textContent || '').trim();
        if (!text && el.querySelector) {
          var img = el.querySelector('img');
          if (img && img.getAttribute) text = img.getAttribute('alt') || '';
        }
        if (text && values.indexOf(text) < 0) values.push(text);
      }
      if (selectedValue && values.indexOf(selectedValue) < 0) values.unshift(selectedValue);
      if (!selectedValue && values.length) selectedValue = values[0];
      if (!selectedValue && !values.length) continue;
      values.sort(function (a, b) {
        if (a === selectedValue) return -1;
        if (b === selectedValue) return 1;
        return 0;
      });
      props.push({ name: propName, values: values, selected: selectedValue });
    }
    return props;
  }

  var capturedAliExpressData = null;
  var capturedAliExpressImages = [];

  function getCapturedAliExpressData() {
    return capturedAliExpressData;
  }

  function getCapturedAliExpressImages() {
    return capturedAliExpressImages;
  }

  function updateDebugAttribute() {
    try {
      var root = document.documentElement;
      if (!root || !root.setAttribute) return;
      var version = '';
      try {
        version = (typeof GM_info !== 'undefined' && GM_info.script) ? GM_info.script.version : '';
      } catch (e) {}
      var adapter = adapterFor(location.href);
      root.setAttribute('data-shoplita-debug', JSON.stringify({
        version: version,
        adapter: adapter ? adapter.id : null,
        captured: !!capturedAliExpressData,
        capturedImages: capturedAliExpressImages,
        domImages: aliexpressDomImages()
      }));
    } catch (e) {}
  }

  function findImageList(node, depth) {
    if (!node || typeof node !== 'object' || depth > 6) return null;
    if (Array.isArray(node.imagePathList) && node.imagePathList.length) return node.imagePathList;
    if (Array.isArray(node.imageList) && node.imageList.length) return node.imageList;
    for (var key in node) {
      if (!hasOwn(node, key)) continue;
      var found = findImageList(node[key], depth + 1);
      if (found) return found;
    }
    return null;
  }

  function findSkuBaseObject(node, depth) {
    if (!node || typeof node !== 'object' || depth > 6) return null;
    if (node.skuBase && (node.skuBase.skus || node.skuBase.props)) return node;
    if (node.skuModule && node.skuModule.skuBase) return node;
    for (var key in node) {
      if (!hasOwn(node, key)) continue;
      var found = findSkuBaseObject(node[key], depth + 1);
      if (found) return found;
    }
    return null;
  }

  function captureAliExpressText(text) {
    if (capturedAliExpressData || !text) return false;
    var source = String(text);
    if (source.length > 3000000 || source.indexOf('"skuBase"') < 0) return false;
    try {
      var parsed = JSON.parse(source);
      var found = findSkuBaseObject(parsed, 0);
      if (!found) return false;
      capturedAliExpressData = found;
      var imageList = findImageList(parsed, 0);
      if (imageList) {
        for (var ii = 0; ii < imageList.length && capturedAliExpressImages.length < 6; ii++) {
          var rawUrl = typeof imageList[ii] === 'string' ? imageList[ii] : (imageList[ii].imgUrl || imageList[ii].url || '');
          var url = aliexpressImageUrl(rawUrl);
          if (url && capturedAliExpressImages.indexOf(url) < 0) capturedAliExpressImages.push(url);
        }
      }
      updateDebugAttribute();
      return true;
    } catch (e) {
      return false;
    }
  }

  function installAliExpressSniffer() {
    if (!/(^|\.)aliexpress\.(com|us)$/.test(location.hostname || '')) return;
    try {
      if (window.__shoplitaAeSniffer) return;
      window.__shoplitaAeSniffer = true;
      var originalFetch = window.fetch;
      if (typeof originalFetch === 'function') {
        window.fetch = function () {
          var args = arguments;
          return originalFetch.apply(this, args).then(function (response) {
            try {
              response.clone().text().then(function (text) {
                if (text && text.indexOf('"skuBase"') >= 0) captureAliExpressText(text);
              }).catch(function () {});
            } catch (e) {}
            return response;
          });
        };
      }
      var XHR = window.XMLHttpRequest;
      if (XHR && XHR.prototype) {
        var originalOpen = XHR.prototype.open;
        var originalSend = XHR.prototype.send;
        XHR.prototype.open = function () {
          return originalOpen.apply(this, arguments);
        };
        XHR.prototype.send = function () {
          var xhr = this;
          xhr.addEventListener('load', function () {
            try {
              var text = xhr.responseText;
              if (text && text.indexOf('"skuBase"') >= 0) captureAliExpressText(text);
            } catch (e) {}
          });
          return originalSend.apply(this, arguments);
        };
      }
    } catch (e) {}
  }

  function aliexpressDomPrice() {
    var el = document.querySelector('[class*="price-default--current"], [class*="price--current"]');
    if (!el) return null;
    return parsePriceNumber(el.textContent);
  }

  function aliexpressImageUrl(src) {
    var text = String(src || '');
    if (!text) return null;
    text = text.replace(/_?\.(avif|webp)$/i, '');
    return text.replace(/_\d+x\d+(?=q\d+)/, '_960x960');
  }

  function aliexpressDomImages() {
    var groups = [
      '[class*="magnifier--image"]',
      '[class*="slider--item"] img, [class*="slider--img"] img',
      '[class*="image-view"] img',
      'img[src*="aliexpress-media"]',
      'img[src*="alicdn"]'
    ];
    var out = [];
    for (var g = 0; g < groups.length && out.length < 6; g++) {
      var imgs = document.querySelectorAll(groups[g]);
      for (var i = 0; i < imgs.length && out.length < 6; i++) {
        var src = '';
        if (imgs[i].getAttribute) {
          src = imgs[i].getAttribute('data-src') || imgs[i].getAttribute('data-lazy-src') || '';
          if (!src) {
            var srcset = imgs[i].getAttribute('srcset');
            if (srcset) {
              var parts = String(srcset).split(',');
              src = String(parts[parts.length - 1] || '').trim().split(' ')[0];
            }
          }
        }
        if (!src) src = imgs[i].src || '';
        var url = aliexpressImageUrl(src);
        if (url && out.indexOf(url) < 0) out.push(url);
      }
    }
    return out;
  }

  function aliexpressDomImage() {
    var images = aliexpressDomImages();
    return images.length ? images[0] : null;
  }

  function aliexpressDomAvailability() {
    var info = document.querySelector('[class*="quantity--info"]');
    if (info) {
      var match = String(info.textContent || '').match(/(\d[\d,]*)\s*available/i);
      if (match) return parseInt(match[1].replace(/,/g, ''), 10) > 0;
    }
    var buy = document.querySelector('[class*="add-to-cart"], [class*="buy-now"]');
    if (buy) {
      var cls = String(buy.className || '');
      if (/disabled/i.test(cls)) return false;
      return true;
    }
    return !domSoldOut();
  }

  function aliexpressDomVariants(props, price, available, name) {
    var variants = [];
    if (!props.length) return variants;
    var combos = [[]];
    for (var i = 0; i < props.length && i < 3; i++) {
      var values = props[i].values.length ? props[i].values : [props[i].selected || ''];
      var next = [];
      for (var c = 0; c < combos.length; c++) {
        for (var v = 0; v < values.length; v++) {
          next.push(combos[c].concat([values[v]]));
          if (next.length >= 200) break;
        }
        if (next.length >= 200) break;
      }
      combos = next;
    }
    for (var k = 0; k < combos.length; k++) {
      var combo = combos[k];
      variants.push({
        id: 'dom-' + k,
        title: combo.filter(Boolean).join(' / ') || name,
        option1: combo[0] || null,
        option2: combo[1] || null,
        option3: combo[2] || null,
        price: Math.round(price * 100),
        compare_at_price: null,
        available: available,
        sku: null
      });
    }
    return variants;
  }

  function collectAliExpress() {
    var captured = getCapturedAliExpressData();
    var raw = captured || findEmbeddedJson(['runParams', '_d_c_', '__INIT_DATA__', '__AER_DATA__']);
    var data = captured ? captured : aliexpressData(raw);
    var skuBase = aliexpressSkuBase(data);
    var name = (data.titleModule && (data.titleModule.subject || data.titleModule.title)) ||
      metaContent('meta[property="og:title"]') || domText('h1[data-pl="product-title"]') ||
      domText('h1') || document.title;
    var image = null;
    if (data.imageModule) {
      var imageList = data.imageModule.imagePathList || data.imageModule.imageList;
      if (Array.isArray(imageList) && imageList.length) {
        var first = imageList[0];
        image = typeof first === 'string' ? first : (first.imgUrl || first.url || null);
      }
    }
    if (!image) image = metaContent('meta[property="og:image"]') || null;
    if (!image) image = aliexpressDomImage();
    if (image && image.indexOf('//') === 0) image = 'https:' + image;
    var currency = (data.priceModule && data.priceModule.currencyCode) || '';
    var basePrice = null;
    if (data.priceModule) {
      var minAmount = data.priceModule.minActivityAmount || data.priceModule.minAmount;
      if (minAmount && minAmount.value != null) basePrice = parseFloat(minAmount.value);
    }
    if (basePrice == null || isNaN(basePrice)) basePrice = domPriceNumber();
    var propNames = [];
    var propOptions = [];
    for (var pn = 0; pn < skuBase.props.length && pn < 3; pn++) {
      var propName = skuBase.props[pn].name || ('Option ' + (pn + 1));
      propNames.push(propName);
      propOptions.push({ name: propName });
    }
    var variants = [];
    for (var i = 0; i < skuBase.skus.length && variants.length < 200; i++) {
      var sku = skuBase.skus[i] || {};
      var skuVal = sku.skuVal || {};
      var price = null;
      if (skuVal.skuActivityAmount && skuVal.skuActivityAmount.value != null) price = parseFloat(skuVal.skuActivityAmount.value);
      else if (skuVal.skuAmount && skuVal.skuAmount.value != null) price = parseFloat(skuVal.skuAmount.value);
      else if (skuVal.skuCalPrice != null) price = parseFloat(skuVal.skuCalPrice);
      if (price == null || isNaN(price)) price = basePrice;
      var values = aliexpressVariantOptions(sku.skuAttr, skuBase.props);
      var byProp = {};
      for (var vi = 0; vi < values.length; vi++) byProp[values[vi].name] = values[vi].value;
      var optionValues = [];
      for (var pi = 0; pi < propNames.length; pi++) optionValues.push(byProp[propNames[pi]] || null);
      var quantity = skuVal.availQuantity != null ? Number(skuVal.availQuantity) :
        (skuVal.inventory != null ? Number(skuVal.inventory) : null);
      variants.push({
        id: sku.skuId || ('sku-' + i),
        title: optionValues.filter(Boolean).join(' / ') || name,
        option1: optionValues[0] || null,
        option2: optionValues[1] || null,
        option3: optionValues[2] || null,
        price: Math.round((price || 0) * 100),
        compare_at_price: null,
        available: aliexpressAvailability(quantity),
        sku: sku.skuId || null
      });
    }
    if (!variants.length) {
      var domProps = aliexpressDomProperties();
      var domAvailable = aliexpressDomAvailability();
      var domPrice = aliexpressDomPrice();
      if (domPrice != null) basePrice = domPrice;
      if (basePrice == null || isNaN(basePrice)) basePrice = domPriceNumber();
      if (basePrice == null || isNaN(basePrice)) return Promise.reject(new Error('could not read AliExpress price'));
      if (domProps.length) {
        variants = aliexpressDomVariants(domProps, basePrice, domAvailable, name);
        propOptions = [];
        for (var dp = 0; dp < domProps.length && dp < 3; dp++) propOptions.push({ name: domProps[dp].name });
      } else {
        variants.push({
          id: 'base',
          title: name,
          option1: null,
          option2: null,
          option3: null,
          price: Math.round(basePrice * 100),
          compare_at_price: null,
          available: domAvailable,
          sku: null
        });
      }
    }
    if (!currency) currency = detectCurrency();
    var domImages = aliexpressDomImages();
    var apiImages = getCapturedAliExpressImages();
    for (var ai = 0; ai < apiImages.length; ai++) {
      if (domImages.indexOf(apiImages[ai]) < 0) domImages.push(apiImages[ai]);
    }
    if (!image && domImages.length) image = domImages[0];
    updateDebugAttribute();
    var match = String(location.pathname).match(/\/(?:item|i)\/(\d+)/);
    var handle = match ? match[1] : currentPageId();
    return Promise.resolve(normalize({
      title: name,
      type: null,
      vendor: null,
      description: '',
      image: image,
      images: domImages,
      options: propOptions,
      variants: variants
    }, handle, currency));
  }

  registerAdapter({
    id: 'aliexpress',
    label: 'AliExpress item pages',
    matches: function () {
      var host = location.hostname || '';
      return (/(^|\.)aliexpress\.com$/.test(host) || /(^|\.)aliexpress\.us$/.test(host)) &&
        /\/(?:item|i)\/\d+/.test(location.pathname || '');
    },
    collect: collectAliExpress
  });

  function collectProduct() {
    var adapter = adapterFor(location.href);
    if (!adapter) return Promise.reject(new Error('unsupported site'));
    return adapter.collect();
  }

  function toTsv(products) {
    var header = [
      'Name', 'Piece', 'Color', 'Size', 'Price', 'Currency', 'In stock',
      'SKU', 'Brand', 'Product code', 'URL', 'Saved at'
    ];
    var rows = [header];
    for (var i = 0; i < products.length; i++) {
      var p = products[i];
      for (var j = 0; j < p.variants.length; j++) {
        var v = p.variants[j];
        rows.push([
          p.name,
          v.piece == null ? '' : v.piece,
          v.color == null ? '' : v.color,
          v.size == null ? '' : v.size,
          v.price.toFixed(2),
          p.currency,
          v.available ? 'yes' : 'no',
          v.sku == null ? '' : v.sku,
          p.brand == null ? '' : p.brand,
          p.productCode == null ? '' : p.productCode,
          v.url,
          p.savedAt == null ? '' : p.savedAt
        ]);
      }
    }
    var lines = [];
    for (var r = 0; r < rows.length; r++) {
      var cells = [];
      for (var c = 0; c < rows[r].length; c++) {
        cells.push(String(rows[r][c]).replace(/[\t\r\n]+/g, ' '));
      }
      lines.push(cells.join('\t'));
    }
    return lines.join('\n');
  }

  function bundleLabel(v) {
    var texts = variantPieceTexts(v);
    var raw = texts.length ? texts[0] : (v.variantTitle || 'Set');
    var cleaned = String(raw).replace(/\([^()]*\)/g, ' ').replace(/\s+/g, ' ').trim();
    return titleCase(cleaned || 'Set');
  }

  function bundlePieceMap(pieces) {
    var map = {};
    for (var i = 0; i < pieces.length; i++) {
      if (!pieces[i].canonical || map[pieces[i].name]) continue;
      map[pieces[i].name] = { color: pieces[i].color || null };
    }
    return map;
  }

  function bundleColor(pieces) {
    var colors = [];
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i].color && colors.indexOf(pieces[i].color) < 0) colors.push(pieces[i].color);
    }
    return colors.join('/') || null;
  }

  function makeSetRow(p, data) {
    var priceRange = variantPriceRange(p);
    return {
      name: p.name,
      handle: p.handle || null,
      source: p.source || null,
      priceMin: priceRange.min,
      priceMax: priceRange.max,
      historyCount: p.history && p.history.length ? p.history.length : 0,
      brand: p.brand || null,
      productCode: p.productCode || null,
      currency: p.currency || '',
      url: p.url || null,
      savedAt: p.savedAt || null,
      type: data.type,
      set: data.set || null,
      color: data.color || null,
      pieces: data.pieces || {},
      total: Math.round((Number(data.total) || 0) * 100) / 100,
      available: !!data.available,
      complete: !!data.complete,
      missing: data.missing || []
    };
  }

  function buildSetRows(products) {
    var rows = [];
    for (var i = 0; i < products.length; i++) {
      var product = products[i];
      var variants = product.variants || [];
      var bundleOrder = [];
      var bundles = {};
      var colorOrder = [];
      var groups = {};
      var typeOrder = [];
      var canonicalTypes = {};
      for (var j = 0; j < variants.length; j++) {
        var variant = variants[j];
        var parts = variantPieces(variant);
        if (parts.bundle) {
          var signature = variantSignature(variant) + '|' + (variant.color || '');
          if (!bundles[signature]) {
            bundles[signature] = {
              label: bundleLabel(variant),
              color: variant.color || bundleColor(parts.pieces) || '',
              pieces: parts.pieces,
              variants: []
            };
            bundleOrder.push(signature);
          }
          bundles[signature].variants.push(variant);
          continue;
        }
        var type = parts.pieces.length ? parts.pieces[0].name : (normalizePieceName(product.type) || 'Item');
        var canonical = parts.pieces.length ? parts.pieces[0].canonical : false;
        var colorKey = variant.color || 'Any';
        if (!groups[colorKey]) {
          groups[colorKey] = { color: colorKey === 'Any' ? '' : colorKey, best: {}, types: [] };
          colorOrder.push(colorKey);
        }
        if (groups[colorKey].types.indexOf(type) < 0) groups[colorKey].types.push(type);
        if (typeOrder.indexOf(type) < 0) typeOrder.push(type);
        if (canonical) canonicalTypes[type] = true;
        var current = groups[colorKey].best[type];
        if (!current || betterVariant(variant, current)) groups[colorKey].best[type] = variant;
      }

      for (var b = 0; b < bundleOrder.length; b++) {
        var bundle = bundles[bundleOrder[b]];
        var bestBundle = null;
        for (var v1 = 0; v1 < bundle.variants.length; v1++) {
          if (!bestBundle || betterVariant(bundle.variants[v1], bestBundle)) bestBundle = bundle.variants[v1];
        }
        rows.push(makeSetRow(product, {
          type: 'bundle',
          set: bundle.label,
          color: bundle.color,
          pieces: bundlePieceMap(bundle.pieces),
          total: bestBundle.price,
          available: bestBundle.available,
          complete: true,
          missing: []
        }));
      }

      var canonicalCount = 0;
      for (var t = 0; t < typeOrder.length; t++) {
        if (canonicalTypes[typeOrder[t]]) canonicalCount++;
      }
      var groupedSet = canonicalCount >= 2;

      for (var c = 0; c < colorOrder.length; c++) {
        var group = groups[colorOrder[c]];
        var pieces = {};
        var total = 0;
        var available = true;
        if (groupedSet) {
          for (var p1 = 0; p1 < group.types.length; p1++) {
            var name = group.types[p1];
            var chosen = group.best[name];
            if (!chosen) continue;
            pieces[name] = {
              price: chosen.price,
              available: !!chosen.available,
              color: chosen.color || null,
              sku: chosen.sku || null,
              title: chosen.variantTitle || null,
              url: chosen.url || null
            };
            total += Number(chosen.price) || 0;
            if (!chosen.available) available = false;
          }
        } else {
          var bestName = null;
          var bestPick = null;
          for (var candidate in group.best) {
            if (!hasOwn(group.best, candidate)) continue;
            if (!bestPick || betterVariant(group.best[candidate], bestPick)) {
              bestPick = group.best[candidate];
              bestName = candidate;
            }
          }
          if (bestPick) {
            pieces[bestName] = {
              price: bestPick.price,
              available: !!bestPick.available,
              color: bestPick.color || null,
              sku: bestPick.sku || null,
              title: bestPick.variantTitle || null,
              url: bestPick.url || null
            };
            total = Number(bestPick.price) || 0;
            available = !!bestPick.available;
          }
        }
        var missing = [];
        if (groupedSet) {
          for (var m = 0; m < typeOrder.length; m++) {
            if (!pieces[typeOrder[m]]) missing.push(typeOrder[m]);
          }
        }
        rows.push(makeSetRow(product, {
          type: groupedSet ? 'set' : 'item',
          set: null,
          color: group.color,
          pieces: pieces,
          total: total,
          available: available,
          complete: groupedSet ? missing.length === 0 : true,
          missing: missing
        }));
      }
    }
    return rows;
  }

  function setMatrix(products) {
    return matrixFromRows(buildSetRows(products));
  }

  function matrixFromRows(sets) {
    var canonicalNames = {};
    for (var k = 0; k < PIECE_KEYWORDS.length; k++) canonicalNames[PIECE_KEYWORDS[k][1]] = true;
    var usage = {};
    var setUsage = {};
    for (var u = 0; u < sets.length; u++) {
      for (var used in sets[u].pieces) {
        if (!hasOwn(sets[u].pieces, used)) continue;
        usage[used] = (usage[used] || 0) + 1;
        if (sets[u].type === 'set') setUsage[used] = true;
      }
    }
    var columns = [];
    for (var i = 0; i < sets.length; i++) {
      for (var name in sets[i].pieces) {
        if (!hasOwn(sets[i].pieces, name) || columns.indexOf(name) >= 0) continue;
        if (!canonicalNames[name]) {
          if (!setUsage[name] || usage[name] < 2 || name.length > 40 || /^\s*-| - /.test(name)) continue;
        }
        columns.push(name);
      }
    }
    var header = ['Product', 'Source', 'Type', 'Set name', 'Color', 'Included pieces'];
    header = header.concat(columns);
    header = header.concat(['Total', 'Currency', 'In stock', 'Complete', 'Missing', 'Liked at', 'Sets', 'Brand', 'Product code', 'URL', 'Saved at']);
    var typeLabels = { set: 'Set', bundle: 'Bundle', item: 'Item' };
    var priority = loadPriority();
    var collections = loadCollections();
    var setsByItem = {};
    for (var col = 0; col < collections.length; col++) {
      var collectionItems = Array.isArray(collections[col].items) ? collections[col].items : [];
      for (var ci = 0; ci < collectionItems.length; ci++) {
        if (!setsByItem[collectionItems[ci]]) setsByItem[collectionItems[ci]] = [];
        setsByItem[collectionItems[ci]].push(collections[col].name);
      }
    }
    var rows = [];
    for (var r = 0; r < sets.length; r++) {
      var row = sets[r];
      var included = [];
      for (var piece in row.pieces) {
        if (hasOwn(row.pieces, piece)) included.push(piece);
      }
      var cells = [
        row.name,
        row.source || '42lolita.com',
        typeLabels[row.type] || row.type,
        row.set == null ? '' : row.set,
        row.color == null ? '' : row.color,
        included.join(', ')
      ];
      for (var c = 0; c < columns.length; c++) {
        var entry = row.pieces[columns[c]];
        cells.push(entry && entry.price != null ? Number(entry.price).toFixed(2) : '');
      }
      var likedStamp = Number(priority[recordItemKey(row)] || 0);
      cells.push(
        row.total.toFixed(2),
        row.currency,
        row.available ? 'yes' : 'no',
        row.complete ? 'yes' : 'no',
        row.missing.join(', '),
        likedStamp > 0 ? new Date(likedStamp).toISOString() : '',
        (setsByItem[recordItemKey(row)] || []).join(', '),
        row.brand == null ? '' : row.brand,
        row.productCode == null ? '' : row.productCode,
        row.url == null ? '' : row.url,
        row.savedAt == null ? '' : row.savedAt
      );
      rows.push(cells);
    }
    return { header: header, rows: rows, sets: sets };
  }

  function rowsToTsv(header, rows) {
    var all = [header].concat(rows);
    var lines = [];
    for (var r = 0; r < all.length; r++) {
      var cells = [];
      for (var c = 0; c < all[r].length; c++) {
        cells.push(String(all[r][c] == null ? '' : all[r][c]).replace(/[\t\r\n]+/g, ' '));
      }
      lines.push(cells.join('\t'));
    }
    return lines.join('\n');
  }

  function toSetTsv(products) {
    var matrix = setMatrix(products);
    return rowsToTsv(matrix.header, matrix.rows);
  }

  function csvCell(value) {
    var text = String(value == null ? '' : value);
    if (/[",\r\n]/.test(text)) text = '"' + text.replace(/"/g, '""') + '"';
    return text;
  }

  function toCsv(header, rows) {
    var all = [header].concat(rows);
    var lines = [];
    for (var r = 0; r < all.length; r++) {
      var cells = [];
      for (var c = 0; c < all[r].length; c++) cells.push(csvCell(all[r][c]));
      lines.push(cells.join(','));
    }
    return '\ufeff' + lines.join('\r\n') + '\r\n';
  }

  function downloadSetsCsv(products) {
    var stamp = new Date().toISOString().slice(0, 10);
    var matrix = setMatrix(products);
    return download('shoplita-set-prices-' + stamp + '.csv', toCsv(matrix.header, matrix.rows), 'text/csv;charset=utf-8');
  }

  function latestSnapshots(products) {
    return dedupeList(products);
  }

  function betterSummaryRow(a, b) {
    var scoreA = (a.complete ? 0 : 2) + (a.available ? 0 : 1);
    var scoreB = (b.complete ? 0 : 2) + (b.available ? 0 : 1);
    if (scoreA !== scoreB) return scoreA < scoreB;
    return Number(a.total) < Number(b.total);
  }

  function buildSummaryRows(products) {
    var rows = buildSetRows(latestSnapshots(products));
    var groups = {};
    var order = [];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      var key = (row.handle || row.name || '') + '|' + (row.color || '');
      if (!groups[key]) {
        groups[key] = row;
        order.push(key);
      } else if (betterSummaryRow(row, groups[key])) {
        groups[key] = row;
      }
    }
    var out = [];
    for (var j = 0; j < order.length; j++) out.push(groups[order[j]]);
    return out;
  }

  function collapseListingRows(rows) {
    var groups = {};
    var order = [];
    for (var i = 0; i < rows.length; i++) {
      var key = recordItemKey(rows[i]);
      if (!groups[key]) {
        groups[key] = { row: rows[i], colors: 1 };
        order.push(key);
      } else {
        groups[key].colors++;
        if (betterSummaryRow(rows[i], groups[key].row)) groups[key].row = rows[i];
      }
    }
    var out = [];
    for (var j = 0; j < order.length; j++) {
      var entry = groups[order[j]];
      entry.row.colorCount = entry.colors;
      out.push(entry.row);
    }
    return out;
  }

  function summaryMatrix(products) {
    return matrixFromRows(buildSummaryRows(products));
  }

  function historyMatrix(products) {
    var header = ['Product', 'Source', 'Piece', 'Color', 'Size', 'Price', 'Currency', 'In stock', 'Saved at'];
    var rows = [];
    for (var i = 0; i < products.length; i++) {
      var product = products[i];
      var source = product.source || '42lolita.com';
      var variantById = {};
      var currentVariants = product.variants || [];
      for (var v = 0; v < currentVariants.length; v++) {
        variantById[String(currentVariants[v].id != null ? currentVariants[v].id : (currentVariants[v].variantTitle || ''))] = currentVariants[v];
      }
      var timeline = Array.isArray(product.history) ? product.history.slice() : [];
      timeline.push(compactSnapshot(product));
      for (var t = 0; t < timeline.length; t++) {
        var snapshot = timeline[t];
        var snapshotVariants = snapshot.variants || [];
        for (var s = 0; s < snapshotVariants.length; s++) {
          var variant = snapshotVariants[s];
          var meta = variantById[String(variant.id)] || {};
          rows.push([
            product.name,
            source,
            meta.piece || meta.variantTitle || '',
            meta.color || '',
            meta.size || '',
            Number(variant.price || 0).toFixed(2),
            snapshot.currency || product.currency || '',
            variant.available ? 'yes' : 'no',
            snapshot.savedAt || ''
          ]);
        }
      }
    }
    return { header: header, rows: rows };
  }

  function toHistoryTsv(products) {
    var matrix = historyMatrix(products);
    return rowsToTsv(matrix.header, matrix.rows);
  }

  function downloadPriceHistoryCsv(products) {
    var stamp = new Date().toISOString().slice(0, 10);
    var matrix = historyMatrix(products);
    return download('shoplita-price-history-' + stamp + '.csv', toCsv(matrix.header, matrix.rows), 'text/csv;charset=utf-8');
  }

  function toSummaryTsv(products) {
    var matrix = summaryMatrix(products);
    return rowsToTsv(matrix.header, matrix.rows);
  }

  function downloadSummaryCsv(products) {
    var stamp = new Date().toISOString().slice(0, 10);
    var matrix = summaryMatrix(products);
    return download('shoplita-wishlist-' + stamp + '.csv', toCsv(matrix.header, matrix.rows), 'text/csv;charset=utf-8');
  }

  var savedPanelEl = null;
  var savedPanelBody = null;
  var savedPanelStatus = null;
  var savedPanelCollections = null;
  var savedPanelOutfits = null;
  var savedPanelTarget = null;
  var savedFilter = { text: '', max: null, inStock: false, collection: null };

  function savedRowEl(row) {
    var wrap = document.createElement('div');
    wrap.style.cssText = 'padding:8px 10px;border-bottom:1px solid #eee;';
    var title = document.createElement('div');
    title.style.cssText = 'display:flex;justify-content:space-between;gap:8px;align-items:baseline;';
    var link = document.createElement('a');
    link.href = row.url || '#';
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.textContent = row.name;
    link.style.cssText = 'color:#c94f86;font-weight:600;text-decoration:none;';
    var price = document.createElement('span');
    price.textContent = (row.currency ? row.currency + ' ' : '') + row.total.toFixed(2);
    price.style.cssText = 'font-weight:700;white-space:nowrap;';
    title.appendChild(link);
    if (isLiked(row)) {
      var badge = document.createElement('span');
      badge.textContent = 'Liked';
      badge.style.cssText = 'color:#c94f86;font-weight:700;white-space:nowrap;';
      title.appendChild(badge);
    }
    title.appendChild(price);

    var metaBits = [];
    if (row.type === 'bundle' && row.set) metaBits.push('Bundle: ' + row.set);
    else if (row.color) metaBits.push('Color: ' + row.color);
    if (row.colorCount > 1) metaBits.push(row.colorCount + ' colors');
    metaBits.push(row.available ? 'in stock' : 'out of stock');
    if (isMarkedUnavailable(row)) metaBits.push('marked unavailable');
    if (row.priceMin != null && row.priceMax > row.priceMin) {
      metaBits.push('range ' + (row.currency ? row.currency + ' ' : '') +
        Number(row.priceMin).toFixed(2) + '\u2013' + Number(row.priceMax).toFixed(2));
    }
    if (row.historyCount > 0) metaBits.push(row.historyCount + ' snapshot(s)');
    if ((row.source || '42lolita.com') !== '42lolita.com') metaBits.push(row.source);
    if (!row.complete && row.missing.length) metaBits.push('missing: ' + row.missing.join(', '));
    if (row.savedAt) metaBits.push(String(row.savedAt).slice(0, 10));
    var meta = document.createElement('div');
    meta.style.cssText = 'color:#666;margin-top:2px;';
    meta.textContent = metaBits.join(' \u00b7 ');

    var names = [];
    for (var pieceName in row.pieces) {
      if (!hasOwn(row.pieces, pieceName)) continue;
      var piece = row.pieces[pieceName];
      names.push(piece && piece.price != null ? pieceName + ' ' + Number(piece.price).toFixed(2) : pieceName);
    }
    var pieces = document.createElement('div');
    pieces.style.cssText = 'color:#444;margin-top:2px;';
    pieces.textContent = names.join(' + ');

    var actions = document.createElement('div');
    actions.style.cssText = 'margin-top:4px;text-align:right;';
    var memberships = collectionsForItem(recordItemKey(row));
    var setSelect = document.createElement('select');
    setSelect.setAttribute('aria-label', 'Add to set');
    setSelect.style.cssText = 'font-size:11px;padding:2px 4px;border:1px solid ' +
      (memberships.length ? '#c94f86' : '#999') + ';border-radius:6px;margin-right:6px;max-width:140px;' +
      (memberships.length ? 'color:#c94f86;font-weight:600;' : '');
    var setDisplay = document.createElement('option');
    setDisplay.value = '__display__';
    var membershipNames = [];
    for (var mn = 0; mn < memberships.length; mn++) membershipNames.push(memberships[mn].name);
    setDisplay.textContent = membershipNames.length ? membershipNames.join(', ') : 'Set\u2026';
    setDisplay.selected = true;
    setSelect.appendChild(setDisplay);
    var allCollections = loadCollections();
    for (var sci = 0; sci < allCollections.length; sci++) {
      var setOption = document.createElement('option');
      setOption.value = allCollections[sci].id;
      var isMember = false;
      for (var mi = 0; mi < memberships.length; mi++) {
        if (memberships[mi].id === allCollections[sci].id) isMember = true;
      }
      setOption.textContent = (isMember ? '\u2713 ' : '') + allCollections[sci].name;
      setSelect.appendChild(setOption);
    }
    var newSetOption = document.createElement('option');
    newSetOption.value = '__new__';
    newSetOption.textContent = '+ New set\u2026';
    setSelect.appendChild(newSetOption);
    setSelect.addEventListener('change', function () {
      if (setSelect.value === '__new__') {
        var name = window.prompt('New set name');
        if (name) {
          var created = createCollection(name);
          if (created) {
            toggleCollectionItem(created.id, recordItemKey(row));
            toast('Saved to "' + created.name + '"!');
          }
        }
      } else if (setSelect.value && setSelect.value !== '__display__') {
        var added = toggleCollectionItem(setSelect.value, recordItemKey(row));
        var collection = findCollection(setSelect.value);
        var collectionName = collection ? collection.name : 'set';
        toast(added ? 'Saved to "' + collectionName + '"!' : 'Removed from "' + collectionName + '"');
      }
      setSelect.value = '__display__';
      renderSavedPanel();
    });
    var like = document.createElement('button');
    like.type = 'button';
    like.textContent = 'I like this!';
    like.style.cssText = 'cursor:pointer;font-size:11px;padding:2px 8px;border:1px solid #c94f86;background:#fff;color:#c94f86;border-radius:6px;margin-right:6px;font-weight:600;';
    like.addEventListener('click', function () {
      animate(like, 'shoplita-anim-like');
      likeItem(row);
      toast('Liked!');
      setTimeout(refreshStatus, 460);
    });
    var compare = document.createElement('button');
    compare.type = 'button';
    compare.textContent = 'Compare';
    compare.style.cssText = 'cursor:pointer;font-size:11px;padding:2px 8px;border:1px solid #777;background:#fff;color:#555;border-radius:6px;margin-right:6px;';
    compare.addEventListener('click', function () {
      compareAddByHandle(recordItemKey(row));
    });
    var remove = document.createElement('button');
    remove.type = 'button';
    remove.textContent = 'Remove';
    remove.style.cssText = 'cursor:pointer;font-size:11px;padding:2px 8px;border:1px solid #cc2b2b;background:#fff;color:#cc2b2b;border-radius:6px;';
    remove.addEventListener('click', function () {
      if (!confirm('Remove "' + row.name + '" from saved items?')) return;
      removeItemGroup(recordItemKey(row));
      refreshStatus();
    });
    actions.appendChild(setSelect);
    actions.appendChild(like);
    actions.appendChild(compare);
    actions.appendChild(remove);

    wrap.appendChild(title);
    wrap.appendChild(meta);
    if (names.length) wrap.appendChild(pieces);
    wrap.appendChild(actions);
    return wrap;
  }

  function collectionChipStyle(active) {
    return 'cursor:pointer;font-size:11px;padding:2px 8px;border-radius:10px;border:1px solid ' +
      (active ? '#c94f86' : '#ccc') + ';background:' + (active ? '#e6659b' : '#fff') +
      ';color:' + (active ? '#fff' : '#555') + ';';
  }

  function renderCollectionsBar() {
    if (!savedPanelCollections) return;
    while (savedPanelCollections.firstChild) savedPanelCollections.removeChild(savedPanelCollections.firstChild);
    var allChip = document.createElement('button');
    allChip.type = 'button';
    allChip.textContent = 'All items';
    allChip.style.cssText = collectionChipStyle(!savedFilter.collection);
    allChip.addEventListener('click', function () {
      savedFilter.collection = null;
      renderSavedPanel();
    });
    savedPanelCollections.appendChild(allChip);
    var collections = loadCollections();
    for (var i = 0; i < collections.length; i++) {
      (function (collection) {
        var wrap = document.createElement('span');
        wrap.style.cssText = 'display:inline-flex;align-items:center;';
        var chip = document.createElement('button');
        chip.type = 'button';
        chip.textContent = collection.name + ' (' + (Array.isArray(collection.items) ? collection.items.length : 0) + ')';
        chip.style.cssText = collectionChipStyle(savedFilter.collection === collection.id);
        chip.addEventListener('click', function () {
          savedFilter.collection = collection.id;
          renderSavedPanel();
        });
        var remove = document.createElement('button');
        remove.type = 'button';
        remove.textContent = '\u00d7';
        remove.setAttribute('aria-label', 'Delete set ' + collection.name);
        remove.style.cssText = 'margin-left:2px;border:none;background:none;color:#999;cursor:pointer;font-size:11px;';
        remove.addEventListener('click', function (event) {
          if (event && event.stopPropagation) event.stopPropagation();
          if (!confirm('Delete set "' + collection.name + '"?')) return;
          deleteCollection(collection.id);
          if (savedFilter.collection === collection.id) savedFilter.collection = null;
          renderSavedPanel();
        });
        wrap.appendChild(chip);
        wrap.appendChild(remove);
        savedPanelCollections.appendChild(wrap);
      })(collections[i]);
    }
    var addChip = document.createElement('button');
    addChip.type = 'button';
    addChip.textContent = '+ New set';
    addChip.style.cssText = collectionChipStyle(false);
    addChip.addEventListener('click', function () {
      var name = window.prompt('New set name');
      if (!name) return;
      createCollection(name);
      renderSavedPanel();
    });
    savedPanelCollections.appendChild(addChip);
  }

  function renderOutfitsBar() {
    if (!savedPanelOutfits) return;
    while (savedPanelOutfits.firstChild) savedPanelOutfits.removeChild(savedPanelOutfits.firstChild);
    var outfits = loadOutfits();
    savedPanelOutfits.style.display = outfits.length ? 'flex' : 'none';
    if (!outfits.length) return;
    var label = document.createElement('div');
    label.textContent = 'Saved outfits';
    label.style.cssText = 'font-size:10px;font-weight:700;color:#666;text-transform:uppercase;letter-spacing:.5px;';
    savedPanelOutfits.appendChild(label);
    for (var i = 0; i < outfits.length; i++) {
      (function (outfit) {
        var row = document.createElement('div');
        row.style.cssText = 'display:flex;align-items:center;gap:6px;font-size:11px;';
        var name = document.createElement('span');
        name.textContent = outfit.name + ' \u00b7 ' + (Array.isArray(outfit.pieces) ? outfit.pieces.length : 0) + ' piece(s)';
        name.style.cssText = 'flex:1;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;';
        var total = document.createElement('span');
        total.textContent = (outfit.currency ? outfit.currency + ' ' : '') + Number(outfit.total || 0).toFixed(2);
        total.style.cssText = 'font-weight:700;white-space:nowrap;';
        var compare = document.createElement('button');
        compare.type = 'button';
        compare.textContent = 'Compare';
        compare.style.cssText = 'cursor:pointer;font-size:10px;padding:1px 6px;border:1px solid #777;background:#fff;color:#555;border-radius:6px;';
        compare.addEventListener('click', function () {
          var record = outfitRecord(outfit);
          if (!record) return;
          setCompareSide('A', record);
          openComparePanel();
        });
        var remove = document.createElement('button');
        remove.type = 'button';
        remove.textContent = '\u00d7';
        remove.setAttribute('aria-label', 'Delete outfit ' + outfit.name);
        remove.style.cssText = 'border:none;background:none;color:#999;cursor:pointer;font-size:12px;';
        remove.addEventListener('click', function () {
          if (!confirm('Delete outfit "' + outfit.name + '"?')) return;
          deleteOutfit(outfit.id);
          renderOutfitsBar();
        });
        row.appendChild(name);
        row.appendChild(total);
        row.appendChild(compare);
        row.appendChild(remove);
        savedPanelOutfits.appendChild(row);
      })(outfits[i]);
    }
  }

  function renderTargetSetBar() {
    if (!savedPanelTarget) return;
    while (savedPanelTarget.firstChild) savedPanelTarget.removeChild(savedPanelTarget.firstChild);
    var label = document.createElement('label');
    label.style.cssText = 'display:flex;align-items:center;gap:6px;font-size:11px;color:#555;';
    label.textContent = 'Add new items to:';
    var select = document.createElement('select');
    select.setAttribute('aria-label', 'Add new items to set');
    select.style.cssText = 'flex:1;padding:2px 6px;border:1px solid #ccc;border-radius:6px;font-size:11px;';
    var none = document.createElement('option');
    none.value = '';
    none.textContent = 'No set';
    select.appendChild(none);
    var collections = loadCollections();
    for (var i = 0; i < collections.length; i++) {
      var option = document.createElement('option');
      option.value = collections[i].id;
      option.textContent = 'Set: ' + collections[i].name;
      select.appendChild(option);
    }
    var newOption = document.createElement('option');
    newOption.value = '__new__';
    newOption.textContent = '+ New set\u2026';
    select.appendChild(newOption);
    select.value = getDefaultSetId() || '';
    select.addEventListener('change', function () {
      if (select.value === '__new__') {
        var name = window.prompt('New set name');
        if (name) {
          var created = createCollection(name);
          if (created) setDefaultSetId(created.id);
        } else {
          setDefaultSetId(null);
        }
      } else {
        setDefaultSetId(select.value || null);
      }
      renderSavedPanel();
    });
    label.appendChild(select);
    savedPanelTarget.appendChild(label);

    var sortRow = document.createElement('div');
    sortRow.style.cssText = 'display:flex;align-items:center;gap:6px;margin-top:4px;font-size:11px;color:#555;';
    var sortLabel = document.createElement('span');
    sortLabel.textContent = 'Sort by:';
    var sortBtn = document.createElement('button');
    sortBtn.type = 'button';
    sortBtn.className = 'shoplita-focus';
    sortBtn.textContent = getSortBy() === 'priority' ? 'Priority' : 'Recently added';
    sortBtn.setAttribute('aria-label', 'Toggle saved items sorting');
    sortBtn.style.cssText = 'cursor:pointer;font-size:11px;padding:2px 8px;border:1px solid #999;background:#fff;color:#555;border-radius:10px;';
    sortBtn.addEventListener('click', function () {
      setSortBy(getSortBy() === 'priority' ? 'recent' : 'priority');
      renderSavedPanel();
    });
    sortRow.appendChild(sortLabel);
    sortRow.appendChild(sortBtn);
    savedPanelTarget.appendChild(sortRow);
  }

  function renderSavedPanel() {
    if (!savedPanelBody) return;
    renderOutfitsBar();
    renderTargetSetBar();
    renderCollectionsBar();
    var rows = collapseListingRows(buildSummaryRows(loadAll()));
    var collectionFilter = null;
    if (savedFilter.collection) {
      var allCollections = loadCollections();
      for (var cf = 0; cf < allCollections.length; cf++) {
        if (allCollections[cf].id === savedFilter.collection) collectionFilter = allCollections[cf];
      }
      if (!collectionFilter) savedFilter.collection = null;
    }
    var filtered = [];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (savedFilter.inStock && !row.available) continue;
      if (collectionFilter && (collectionFilter.items || []).indexOf(recordItemKey(row)) < 0) continue;
      if (savedFilter.max != null && Number(row.total) > savedFilter.max) continue;
      if (savedFilter.text) {
        var hay = (row.name + ' ' + (row.color || '') + ' ' + (row.set || '') + ' ' + Object.keys(row.pieces).join(' ')).toLowerCase();
        if (hay.indexOf(savedFilter.text) < 0) continue;
      }
      filtered.push(row);
    }
    var sortBy = getSortBy();
    function byRecency(a, b) {
      var aDate = String(a.savedAt || '');
      var bDate = String(b.savedAt || '');
      if (aDate !== bDate) return aDate < bDate ? 1 : -1;
      return Number(a.total) - Number(b.total);
    }
    var priorityRows = [];
    var otherRows = [];
    var likedCount = 0;
    for (var lc = 0; lc < filtered.length; lc++) {
      if (priorityScore(filtered[lc]) > 0) likedCount++;
    }
    if (sortBy === 'priority') {
      for (var f = 0; f < filtered.length; f++) {
        if (priorityScore(filtered[f]) > 0) priorityRows.push(filtered[f]);
        else otherRows.push(filtered[f]);
      }
      priorityRows.sort(function (a, b) {
        var diff = priorityScore(b) - priorityScore(a);
        if (diff) return diff;
        return byRecency(a, b);
      });
      otherRows.sort(byRecency);
    } else {
      filtered.sort(byRecency);
    }
    while (savedPanelBody.firstChild) savedPanelBody.removeChild(savedPanelBody.firstChild);
    function addSection(title, sectionRows) {
      var head = document.createElement('div');
      head.textContent = title;
      head.style.cssText = 'padding:6px 10px;background:#f6f6f6;font-weight:700;color:#555;text-transform:uppercase;font-size:10px;letter-spacing:.5px;';
      savedPanelBody.appendChild(head);
      for (var s = 0; s < sectionRows.length; s++) savedPanelBody.appendChild(savedRowEl(sectionRows[s]));
    }
    if (!filtered.length) {
      var empty = document.createElement('div');
      empty.textContent = rows.length ? 'No saved items match the filters.' : 'Nothing saved yet.';
      empty.style.cssText = 'padding:12px;color:#888;';
      savedPanelBody.appendChild(empty);
    } else if (sortBy === 'priority') {
      if (priorityRows.length) addSection('Priority', priorityRows);
      if (otherRows.length) addSection(priorityRows.length ? 'All items' : 'Items', otherRows);
    } else {
      for (var r2 = 0; r2 < filtered.length; r2++) savedPanelBody.appendChild(savedRowEl(filtered[r2]));
    }
    if (savedPanelStatus) {
      var keys = {};
      for (var k = 0; k < filtered.length; k++) keys[recordItemKey(filtered[k])] = true;
      savedPanelStatus.textContent = filtered.length + ' outfit row(s) \u00b7 ' + Object.keys(keys).length + ' saved item(s)' +
        (likedCount ? ' \u00b7 ' + likedCount + ' priority' : '');
    }
  }

  function buildSavedPanel() {
    var panel = document.createElement('div');
    panel.className = 'shoplita-panel';
    panel.style.cssText =
      'display:none;flex-direction:column;position:fixed;right:16px;top:16px;bottom:200px;width:400px;max-width:calc(100vw - 32px);' +
      'background:#fff;color:#222;border:1px solid #ddd;border-radius:10px;z-index:999998;' +
      'overflow:hidden;box-shadow:0 4px 18px rgba(0,0,0,.25);font:12px/1.4 sans-serif;';

    var head = document.createElement('div');
    head.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:8px 10px;border-bottom:1px solid #eee;';
    var heading = document.createElement('strong');
    heading.textContent = 'Saved items';
    var close = document.createElement('button');
    close.type = 'button';
    close.textContent = '\u00d7';
    close.setAttribute('aria-label', 'Close saved items');
    close.style.cssText = 'cursor:pointer;border:none;background:none;font-size:18px;line-height:1;';
    close.addEventListener('click', function () { panel.style.display = 'none'; });
    var about = document.createElement('button');
    about.type = 'button';
    about.className = 'shoplita-focus';
    about.textContent = 'About';
    about.setAttribute('aria-label', 'About Shoplita');
    about.setAttribute('aria-expanded', 'false');
    about.style.cssText = 'cursor:pointer;border:none;background:none;color:#c94f86;font-size:11px;font-weight:600;';
    about.addEventListener('click', function () {
      var open = aboutBar.style.display !== 'flex';
      aboutBar.style.display = open ? 'flex' : 'none';
      about.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    var headRight = document.createElement('div');
    headRight.style.cssText = 'display:flex;align-items:center;gap:8px;';
    headRight.appendChild(about);
    headRight.appendChild(close);
    head.appendChild(heading);
    head.appendChild(headRight);

    var filters = document.createElement('div');
    filters.style.cssText = 'display:flex;gap:6px;align-items:center;padding:8px 10px;border-bottom:1px solid #eee;flex-wrap:wrap;';
    var search = document.createElement('input');
    search.type = 'search';
    search.placeholder = 'search name / piece';
    search.setAttribute('aria-label', 'Search saved items');
    search.style.cssText = 'flex:1;min-width:120px;padding:4px 6px;border:1px solid #ccc;border-radius:6px;';
    var max = document.createElement('input');
    max.type = 'number';
    max.min = '0';
    max.placeholder = 'max price';
    max.setAttribute('aria-label', 'Maximum price');
    max.style.cssText = 'width:84px;padding:4px 6px;border:1px solid #ccc;border-radius:6px;';
    var stockLabel = document.createElement('label');
    stockLabel.style.cssText = 'display:flex;gap:4px;align-items:center;white-space:nowrap;';
    var stockBox = document.createElement('input');
    stockBox.type = 'checkbox';
    stockLabel.appendChild(stockBox);
    stockLabel.appendChild(document.createTextNode('in stock only'));
    search.addEventListener('input', function () {
      savedFilter.text = search.value.trim().toLowerCase();
      renderSavedPanel();
    });
    max.addEventListener('input', function () {
      var limit = parseFloat(max.value);
      savedFilter.max = isNaN(limit) ? null : limit;
      renderSavedPanel();
    });
    stockBox.addEventListener('change', function () {
      savedFilter.inStock = stockBox.checked;
      renderSavedPanel();
    });
    filters.appendChild(search);
    filters.appendChild(max);
    filters.appendChild(stockLabel);

    var body = document.createElement('div');
    body.style.cssText = 'flex:1;overflow:auto;';

    var status = document.createElement('div');
    status.style.cssText = 'padding:5px 10px;border-top:1px solid #eee;color:#666;background:#fafafa;';

    var targetBar = document.createElement('div');
    targetBar.style.cssText = 'padding:6px 10px;border-bottom:1px solid #eee;';
    savedPanelTarget = targetBar;
    var outfitsBar = document.createElement('div');
    outfitsBar.style.cssText = 'display:none;flex-direction:column;gap:4px;padding:6px 10px;border-bottom:1px solid #eee;';
    savedPanelOutfits = outfitsBar;
    var collectionsBar = document.createElement('div');
    collectionsBar.style.cssText = 'display:flex;gap:4px;flex-wrap:wrap;padding:6px 10px;border-bottom:1px solid #eee;';
    savedPanelCollections = collectionsBar;

    var aboutBar = document.createElement('div');
    aboutBar.style.cssText = 'display:none;flex-direction:column;gap:2px;padding:8px 10px;border-bottom:1px solid #eee;background:#fafafa;font-size:11px;color:#444;';
    var aboutTitle = document.createElement('strong');
    aboutTitle.textContent = 'Works on:';
    aboutBar.appendChild(aboutTitle);
    for (var ai = 0; ai < ADAPTERS.length; ai++) {
      if (!ADAPTERS[ai].label) continue;
      var aboutItem = document.createElement('div');
      aboutItem.textContent = '\u2022 ' + ADAPTERS[ai].label;
      aboutBar.appendChild(aboutItem);
    }
    var aboutNote = document.createElement('div');
    aboutNote.textContent = 'Import share files from other Shoplita users via Import data.';
    aboutNote.style.cssText = 'margin-top:4px;color:#666;';
    aboutBar.appendChild(aboutNote);
    var aboutVersion = document.createElement('div');
    var scriptVersion = '';
    try {
      scriptVersion = (typeof GM_info !== 'undefined' && GM_info.script && GM_info.script.version) ? GM_info.script.version : '';
    } catch (e) {}
    aboutVersion.textContent = 'Shoplita' + (scriptVersion ? ' v' + scriptVersion : '');
    aboutVersion.style.cssText = 'color:#888;';
    aboutBar.appendChild(aboutVersion);

    panel.appendChild(head);
    panel.appendChild(filters);
    panel.appendChild(targetBar);
    panel.appendChild(outfitsBar);
    panel.appendChild(collectionsBar);
    panel.appendChild(aboutBar);
    panel.appendChild(body);
    panel.appendChild(status);
    document.body.appendChild(panel);
    savedPanelEl = panel;
    savedPanelBody = body;
    savedPanelStatus = status;
  }

  function toggleSavedPanel(show) {
    if (!savedPanelEl) buildSavedPanel();
    var visible = savedPanelEl.style.display !== 'none';
    var next = show === undefined ? !visible : !!show;
    savedPanelEl.style.display = next ? 'flex' : 'none';
    if (next) renderSavedPanel();
  }

  var compareEl = null;
  var compareState = { a: null, b: null, rankBy: 'recent', filterSet: null };

  function variantTypeName(v) {
    var parsed = variantPieces(v);
    if (parsed.bundle) {
      var label = bundleLabel(v);
      var stripped = stripColorWords(label);
      return stripped ? titleCase(stripped) : label;
    }
    return parsed.pieces.length ? parsed.pieces[0].name : (normalizePieceName(v.piece) || 'Item');
  }

  function compareOptions(record) {
    var variants = (record && record.variants) || [];
    var types = [];
    var colors = [];
    var index = {};
    for (var i = 0; i < variants.length; i++) {
      var variant = variants[i];
      var type = variantTypeName(variant);
      var color = variant.color || '';
      if (!index[type]) {
        index[type] = { name: type, byColor: {}, variants: [] };
        types.push(index[type]);
      }
      if (colors.indexOf(color) < 0) colors.push(color);
      if (index[type].variants.length < 200) index[type].variants.push(variant);
      var current = index[type].byColor[color];
      if (!current || betterVariant(variant, current)) index[type].byColor[color] = variant;
    }
    return { types: types, colors: colors };
  }

  function firstColorVariant(type) {
    for (var color in type.byColor) {
      if (hasOwn(type.byColor, color)) return type.byColor[color];
    }
    return null;
  }

  function mainTypeName(types) {
    var priority = ['OP', 'JSK', 'Dress', 'Skirt', 'Salopette', 'Top', 'Corset', 'Vest', 'Bolero', 'Blouse', 'Cape', 'Coat'];
    for (var p = 0; p < priority.length; p++) {
      for (var i = 0; i < types.length; i++) {
        if (types[i].name === priority[p]) return types[i].name;
      }
    }
    return types.length ? types[0].name : null;
  }

  function newCompareSide(record) {
    var options = compareOptions(record);
    var side = {
      record: record,
      options: options,
      color: options.colors[0] || '',
      picks: {},
      include: {}
    };
    side.main = mainTypeName(options.types);
    for (var i = 0; i < options.types.length; i++) {
      var type = options.types[i];
      var pick = type.byColor[side.color] || firstColorVariant(type);
      side.picks[type.name] = pick;
      side.include[type.name] = type.name === side.main;
    }
    return side;
  }

  function setCompareColor(side, color) {
    side.color = color;
    for (var i = 0; i < side.options.types.length; i++) {
      var type = side.options.types[i];
      var pick = type.byColor[color] || null;
      side.picks[type.name] = pick;
      if (!pick) side.include[type.name] = false;
    }
  }

  function sideTotal(side) {
    if (!side) return 0;
    var total = 0;
    for (var name in side.include) {
      if (!hasOwn(side.include, name) || !side.include[name]) continue;
      var pick = side.picks[name];
      if (pick) total += Number(pick.price) || 0;
    }
    return Math.round(total * 100) / 100;
  }

  function variantPriceRange(record) {
    var variants = (record && record.variants) || [];
    var min = null;
    var max = null;
    for (var i = 0; i < variants.length; i++) {
      var price = Number(variants[i].price);
      if (isNaN(price)) continue;
      if (min == null || price < min) min = price;
      if (max == null || price > max) max = price;
    }
    return { min: min, max: max };
  }

  function collectComparePieces() {
    var pieces = [];
    var sides = [compareState.a, compareState.b];
    for (var s = 0; s < sides.length; s++) {
      var side = sides[s];
      if (!side) continue;
      for (var typeName in side.include) {
        if (!hasOwn(side.include, typeName) || !side.include[typeName]) continue;
        var pick = side.picks[typeName];
        if (!pick) continue;
        pieces.push({
          name: typeName,
          price: Number(pick.price) || 0,
          color: pick.color || side.color || null,
          available: !!pick.available,
          itemName: side.record.name,
          itemUrl: side.record.url || null,
          source: side.record.source || null,
          variantTitle: pick.variantTitle || null
        });
      }
    }
    return pieces;
  }

  function loadCompareImage(record, img) {
    if (!record || record.image) return;
    var match = String(record.url || '').match(/\/products\/([^/?#]+)/);
    var handle = record.handle || (match && match[1]);
    if (!handle) return;
    fetchJson(recordOrigin(record) + '/products/' + encodeURIComponent(handle) + '.js').then(function (product) {
      var image = firstImage(product.featured_image || product.images);
      if (image) {
        record.image = image;
        img.src = image;
      }
    }).catch(function () {});
  }

  function closeCompare() {
    if (compareEl) compareEl.style.display = 'none';
  }

  function compareRecordKey(side) {
    return side && side.record ? recordItemKey(side.record) : null;
  }

  function findSnapshotByKey(key) {
    if (!key) return null;
    var records = latestSnapshots(loadAll());
    for (var i = 0; i < records.length; i++) {
      if (recordItemKey(records[i]) === key) return records[i];
    }
    if (key.indexOf('shoplita.set|') === 0) {
      return collectionRecord(findCollection(key.slice('shoplita.set|'.length)));
    }
    if (key.indexOf('shoplita.outfit|') === 0) {
      var outfits = loadOutfits();
      var outfitId = key.slice('shoplita.outfit|'.length);
      for (var o = 0; o < outfits.length; o++) {
        if (outfits[o].id === outfitId) return outfitRecord(outfits[o]);
      }
    }
    return null;
  }

  function loadCompareKeys() {
    try {
      var raw = typeof GM_getValue === 'function'
        ? GM_getValue(COMPARE_KEY, '{}')
        : (localStorage.getItem(COMPARE_KEY) || '{}');
      var map = JSON.parse(raw);
      return map && typeof map === 'object' ? map : {};
    } catch (e) {
      return {};
    }
  }

  function saveCompareKeys(map) {
    var raw = JSON.stringify(map);
    if (typeof GM_setValue === 'function') GM_setValue(COMPARE_KEY, raw);
    else localStorage.setItem(COMPARE_KEY, raw);
  }

  function persistCompareState() {
    saveCompareKeys({
      a: compareRecordKey(compareState.a),
      b: compareRecordKey(compareState.b),
      rank: compareState.rankBy || 'recent',
      filter: compareState.filterSet || null
    });
  }

  function restoreCompareState() {
    var keys = loadCompareKeys();
    if (keys.rank) compareState.rankBy = keys.rank;
    if (keys.filter) compareState.filterSet = keys.filter;
    if (compareState.a || compareState.b) return;
    if (!keys.a && !keys.b) return;
    var recordA = keys.a ? findSnapshotByKey(keys.a) : null;
    var recordB = keys.b ? findSnapshotByKey(keys.b) : null;
    if (recordA) compareState.a = newCompareSide(recordA);
    if (recordB) compareState.b = newCompareSide(recordB);
  }

  function compareRecords() {
    var records = latestSnapshots(loadAll());
    if (!compareState.filterSet) return records;
    var collection = findCollection(compareState.filterSet);
    if (!collection || !Array.isArray(collection.items)) return records;
    var allowed = {};
    for (var i = 0; i < collection.items.length; i++) allowed[collection.items[i]] = true;
    var out = [];
    for (var j = 0; j < records.length; j++) {
      if (allowed[recordItemKey(records[j])]) out.push(records[j]);
    }
    return out;
  }

  function compareAddByHandle(key) {
    var found = findSnapshotByKey(key);
    if (!found) return;
    if (compareRecordKey(compareState.a) !== key && compareRecordKey(compareState.b) !== key) {
      if (!compareState.a) setCompareSide('A', found);
      else setCompareSide('B', found);
    }
    openComparePanel();
  }

  function compareOrder(records) {
    var unavailable = loadUnavailable();
    var available = [];
    var blocked = [];
    for (var i = 0; i < records.length; i++) {
      if (unavailable[recordItemKey(records[i])]) blocked.push(records[i]);
      else available.push(records[i]);
    }
    var rankByPriority = compareState.rankBy === 'priority';
    function sorter(a, b) {
      if (rankByPriority) {
        var diff = priorityScore(b) - priorityScore(a);
        if (diff) return diff;
      }
      var aDate = String(a.savedAt || '');
      var bDate = String(b.savedAt || '');
      if (aDate === bDate) return 0;
      return aDate > bDate ? -1 : 1;
    }
    available.sort(sorter);
    blocked.sort(sorter);
    return { available: available, blocked: blocked };
  }

  function setCompareSide(label, record) {
    var side = record ? newCompareSide(record) : null;
    if (label === 'A') compareState.a = side;
    else compareState.b = side;
    persistCompareState();
  }

  function nextAvailableRecord(currentKey, otherKey) {
    var order = compareOrder(compareRecords());
    var list = order.available;
    if (!list.length) return null;
    var start = 0;
    for (var i = 0; i < list.length; i++) {
      if (recordItemKey(list[i]) === currentKey) { start = i + 1; break; }
    }
    for (var step = 0; step < list.length; step++) {
      var candidate = list[(start + step) % list.length];
      var key = recordItemKey(candidate);
      if (key !== currentKey && key !== otherKey) return candidate;
    }
    return null;
  }

  var comboDocBound = false;
  var activeCombo = null;

  function bindComboDocument() {
    if (comboDocBound) return;
    comboDocBound = true;
    document.addEventListener('click', function (event) {
      if (!activeCombo || !event || !event.target) return;
      var wrap = activeCombo.wrap;
      if (wrap && wrap.contains && !wrap.contains(event.target)) activeCombo.close();
    });
  }

  function makeSearchableSelect(placeholder, ariaLabel, groups, selectedKey, onSelect) {
    bindComboDocument();
    var wrap = document.createElement('span');
    wrap.style.cssText = 'position:relative;display:inline-block;min-width:200px;max-width:280px;flex:1 1 200px;';

    var input = document.createElement('input');
    input.type = 'text';
    input.placeholder = placeholder;
    input.className = 'shoplita-focus';
    input.setAttribute('role', 'combobox');
    input.setAttribute('aria-expanded', 'false');
    input.setAttribute('aria-autocomplete', 'list');
    input.setAttribute('aria-label', ariaLabel);
    input.style.cssText = 'width:100%;padding:4px 6px;border:1px solid #ccc;border-radius:6px;font-size:12px;';

    var list = document.createElement('div');
    list.setAttribute('role', 'listbox');
    list.setAttribute('aria-label', ariaLabel + ' options');
    list.style.cssText = 'position:absolute;z-index:20;left:0;right:0;top:100%;margin-top:2px;max-height:260px;overflow:auto;' +
      'background:#fff;border:1px solid #ccc;border-radius:8px;box-shadow:0 4px 14px rgba(0,0,0,.18);display:none;padding:4px 0;';

    var entries = [];
    var headers = [];
    var counter = 0;
    var activeIndex = -1;

    function addEntry(value, label, disabled, isHeader) {
      var el = document.createElement('div');
      el.id = 'shoplita-option-' + (++counter);
      el.textContent = label;
      if (isHeader) {
        el.setAttribute('role', 'presentation');
        el.style.cssText = 'padding:5px 10px;font-size:10px;font-weight:700;color:#888;text-transform:uppercase;letter-spacing:.5px;background:#fafafa;';
        headers.push(el);
      } else {
        el.setAttribute('role', 'option');
        el.setAttribute('aria-selected', value === selectedKey ? 'true' : 'false');
        if (disabled) el.setAttribute('aria-disabled', 'true');
        el.style.cssText = 'padding:5px 10px;font-size:12px;' +
          (disabled ? 'color:#aaa;cursor:default;' : 'cursor:pointer;') +
          (value === selectedKey ? 'font-weight:700;background:#fdf0f6;' : '');
        entries.push({ el: el, value: value, label: label, disabled: !!disabled });
        if (!disabled) {
          el.addEventListener('click', function () { choose(value); });
          el.addEventListener('mouseenter', function () { setActiveByValue(value); });
        }
      }
      list.appendChild(el);
    }

    for (var g = 0; g < groups.length; g++) {
      if (!groups[g].options || !groups[g].options.length) continue;
      if (groups[g].label) addEntry(null, groups[g].label, true, true);
      for (var o = 0; o < groups[g].options.length; o++) {
        var option = groups[g].options[o];
        addEntry(option.value, option.label, option.disabled, false);
      }
    }

    function visibleEntries() {
      var out = [];
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].el.style.display !== 'none') out.push(entries[i]);
      }
      return out;
    }

    function setActive(index) {
      var visible = visibleEntries();
      if (!visible.length) return;
      if (index < 0) index = visible.length - 1;
      if (index >= visible.length) index = 0;
      activeIndex = index;
      for (var i = 0; i < visible.length; i++) {
        visible[i].el.setAttribute('aria-selected', i === index ? 'true' : 'false');
      }
      input.setAttribute('aria-activedescendant', visible[index].el.id);
    }

    function setActiveByValue(value) {
      var visible = visibleEntries();
      for (var i = 0; i < visible.length; i++) {
        if (visible[i].value === value) { setActive(i); return; }
      }
    }

    function open() {
      list.style.display = 'block';
      input.setAttribute('aria-expanded', 'true');
      activeCombo = { wrap: wrap, close: close };
    }
    function close() {
      list.style.display = 'none';
      input.setAttribute('aria-expanded', 'false');
      if (input.removeAttribute) input.removeAttribute('aria-activedescendant');
      if (activeCombo && activeCombo.wrap === wrap) activeCombo = null;
    }
    function choose(value) {
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].value === value) {
          input.value = entries[i].label;
          close();
          onSelect(value);
          return;
        }
      }
    }
    function filter() {
      var text = String(input.value || '').toLowerCase();
      for (var i = 0; i < entries.length; i++) {
        entries[i].el.style.display = !text || entries[i].label.toLowerCase().indexOf(text) >= 0 ? '' : 'none';
      }
      for (var h = 0; h < headers.length; h++) {
        headers[h].style.display = text ? 'none' : '';
      }
      activeIndex = -1;
    }

    input.addEventListener('focus', function () { open(); });
    input.addEventListener('click', function () { open(); });
    input.addEventListener('input', function () { filter(); open(); });
    input.addEventListener('keydown', function (event) {
      var key = event && event.key;
      if (key === 'ArrowDown') {
        if (event.preventDefault) event.preventDefault();
        open();
        setActive(activeIndex + 1);
      } else if (key === 'ArrowUp') {
        if (event.preventDefault) event.preventDefault();
        open();
        setActive(activeIndex - 1);
      } else if (key === 'Enter') {
        var visible = visibleEntries();
        if (visible.length) {
          if (event.preventDefault) event.preventDefault();
          choose(visible[activeIndex >= 0 ? activeIndex : 0].value);
        }
      } else if (key === 'Escape') {
        close();
      }
    });
    input.addEventListener('blur', function () {
      setTimeout(close, 150);
    });

    for (var s = 0; s < entries.length; s++) {
      if (entries[s].value === selectedKey) input.value = entries[s].label;
    }

    wrap.appendChild(input);
    wrap.appendChild(list);
    return wrap;
  }

  function makeCompareSelect(label, records, selected, onChange) {
    var selectedKey = '';
    if (selected) {
      if (selected.source === 'shoplita.set') selectedKey = 'set:' + selected.handle;
      else if (selected.source === 'shoplita.outfit') selectedKey = 'fit:' + selected.handle;
      else selectedKey = recordItemKey(selected);
    }
    var order = compareOrder(records);
    var groups = [];
    var availableOptions = [];
    for (var i = 0; i < order.available.length; i++) {
      var record = order.available[i];
      availableOptions.push({
        value: recordItemKey(record),
        label: record.name + (record.savedAt ? ' (' + String(record.savedAt).slice(0, 10) + ')' : '')
      });
    }
    groups.push({ label: 'Available', options: availableOptions });
    if (order.blocked.length) {
      var blockedOptions = [];
      for (var b = 0; b < order.blocked.length; b++) {
        blockedOptions.push({ value: recordItemKey(order.blocked[b]), label: order.blocked[b].name });
      }
      groups.push({ label: 'Unavailable ----', options: blockedOptions });
    }
    var collections = loadCollections();
    if (collections.length) {
      var setOptions = [];
      for (var si = 0; si < collections.length; si++) {
        setOptions.push({
          value: 'set:' + collections[si].id,
          label: 'Set: ' + collections[si].name + ' (' +
            (Array.isArray(collections[si].items) ? collections[si].items.length : 0) + ')'
        });
      }
      groups.push({ label: 'Sets ----', options: setOptions });
    }
    var outfits = loadOutfits();
    if (outfits.length) {
      var outfitOptions = [];
      for (var oi = 0; oi < outfits.length; oi++) {
        outfitOptions.push({
          value: 'fit:' + outfits[oi].id,
          label: 'Outfit: ' + outfits[oi].name + ' (' +
            (Array.isArray(outfits[oi].pieces) ? outfits[oi].pieces.length : 0) + ')'
        });
      }
      groups.push({ label: 'Outfits ----', options: outfitOptions });
    }
    return makeSearchableSelect('Item ' + label + ': search\u2026', 'Compare item ' + label, groups, selectedKey, function (value) {
      if (value.indexOf('set:') === 0) {
        onChange(collectionRecord(findCollection(value.slice(4))));
        return;
      }
      if (value.indexOf('fit:') === 0) {
        var list = loadOutfits();
        var outfitId = value.slice(4);
        for (var f = 0; f < list.length; f++) {
          if (list[f].id === outfitId) { onChange(outfitRecord(list[f])); return; }
        }
        onChange(null);
        return;
      }
      onChange(findSnapshotByKey(value));
    });
  }

  function renderCompareTypeRow(side, type) {
    var row = document.createElement('div');
    row.style.cssText = 'display:flex;align-items:center;gap:6px;';
    var box = document.createElement('input');
    box.type = 'checkbox';
    box.checked = !!side.include[type.name];
    box.setAttribute('aria-label', 'Include ' + type.name);
    var pick = side.picks[type.name];
    box.addEventListener('change', function () {
      side.include[type.name] = box.checked;
      renderCompare();
    });
    var name = document.createElement('span');
    name.textContent = type.name;
    name.style.cssText = 'min-width:86px;font-weight:600;';
    var select = document.createElement('select');
    select.style.cssText = 'flex:1;padding:3px 6px;border:1px solid #ccc;border-radius:6px;';
    var variantList = Array.isArray(type.variants) && type.variants.length ? type.variants : [];
    if (!variantList.length) {
      for (var c0 = 0; c0 < side.options.colors.length; c0++) {
        if (type.byColor[side.options.colors[c0]]) variantList.push(type.byColor[side.options.colors[c0]]);
      }
    }
    var hasOption = false;
    var anyAvailable = false;
    for (var vi = 0; vi < variantList.length; vi++) {
      var variant = variantList[vi];
      hasOption = true;
      if (variant.available) anyAvailable = true;
      var option = document.createElement('option');
      option.value = String(vi);
      option.textContent = (variant.color || 'default') + (variant.size ? ' \u00b7 ' + variant.size : '') +
        ' \u00b7 ' + Number(variant.price).toFixed(2) +
        (variant.available ? '' : ' \u00b7 out of stock');
      option.selected = pick === variant;
      select.appendChild(option);
    }
    if (hasOption && !anyAvailable) {
      row.style.opacity = '0.6';
      name.textContent = type.name + ' (sold out)';
    }
    if (!pick) {
      var placeholder = document.createElement('option');
      placeholder.textContent = 'no ' + (side.color || 'default') + ' option';
      placeholder.selected = true;
      select.insertBefore(placeholder, select.firstChild || null);
      box.checked = false;
      box.disabled = true;
    }
    if (!hasOption) select.disabled = true;
    select.addEventListener('change', function () {
      var chosen = variantList[parseInt(select.value, 10)] || null;
      side.picks[type.name] = chosen;
      side.include[type.name] = !!chosen;
      renderCompare();
    });
    row.appendChild(box);
    row.appendChild(name);
    row.appendChild(select);
    return row;
  }

  function renderCompareSide(side, label) {
    var col = document.createElement('div');
    col.style.cssText = 'flex:1 1 280px;min-width:0;display:flex;flex-direction:column;gap:8px;';
    if (!side) {
      var empty = document.createElement('div');
      empty.textContent = 'Item ' + label + ': pick a saved item above.';
      empty.style.cssText = 'color:#888;padding:20px 0;';
      col.appendChild(empty);
      return col;
    }
    var record = side.record;
    var img = document.createElement('img');
    img.alt = record.name;
    img.style.cssText = 'width:100%;height:220px;object-fit:contain;background:#f4f4f4;border-radius:8px;';
    var imageCandidates = [];
    if (record.image) imageCandidates.push(record.image);
    if (Array.isArray(record.images)) {
      for (var ic = 0; ic < record.images.length; ic++) {
        if (record.images[ic] && imageCandidates.indexOf(record.images[ic]) < 0) imageCandidates.push(record.images[ic]);
      }
    }
    if (imageCandidates.length) {
      var imageIndex = 0;
      img.src = imageCandidates[0];
      img.addEventListener('error', function () {
        imageIndex++;
        if (imageIndex < imageCandidates.length) img.src = imageCandidates[imageIndex];
      });
    } else {
      loadCompareImage(record, img);
    }
    col.appendChild(img);
    if (!imageCandidates.length && String(record.source || '').indexOf('aliexpress') === 0) {
      var imageNote = document.createElement('div');
      imageNote.textContent = 'No image saved - re-save this listing to capture it.';
      imageNote.style.cssText = 'color:#999;font-size:10px;text-align:center;';
      col.appendChild(imageNote);
    }

    var link = document.createElement('a');
    link.href = record.url || '#';
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.textContent = record.name;
    link.style.cssText = 'color:#c94f86;font-weight:600;text-decoration:none;';
    col.appendChild(link);

    var source = record.source || '42lolita.com';
    if (source.indexOf('shoplita.') !== 0) {
      var sourceLine = document.createElement('div');
      sourceLine.style.cssText = 'color:#888;font-size:11px;';
      sourceLine.textContent = 'Listing from ' + source;
      col.appendChild(sourceLine);
    }
    var range = variantPriceRange(record);
    if (range.min != null) {
      var priceLine = document.createElement('div');
      priceLine.style.cssText = 'color:#666;font-size:11px;';
      var currencyPrefix = record.currency ? record.currency + ' ' : '';
      priceLine.textContent = range.max > range.min
        ? 'Price range: ' + currencyPrefix + range.min.toFixed(2) + '\u2013' + range.max.toFixed(2)
        : 'Price: ' + currencyPrefix + range.min.toFixed(2);
      col.appendChild(priceLine);
    }
    var historyCount = Array.isArray(record.history) ? record.history.length : 0;
    if (historyCount > 0) {
      var historyLine = document.createElement('div');
      historyLine.style.cssText = 'color:#888;font-size:11px;';
      historyLine.textContent = 'Price history: ' + historyCount + ' snapshot(s)';
      col.appendChild(historyLine);
    }

    var likeRow = document.createElement('div');
    likeRow.style.cssText = 'display:flex;align-items:center;gap:6px;flex-wrap:wrap;';
    var like = document.createElement('button');
    like.type = 'button';
    like.textContent = 'I like this!';
    like.style.cssText = 'cursor:pointer;font-size:12px;padding:4px 10px;border:1px solid #c94f86;background:#fff;color:#c94f86;border-radius:12px;font-weight:600;';
    like.addEventListener('click', function () {
      animate(like, 'shoplita-anim-like');
      likeItem(record);
      scoreLabel.textContent = isLiked(record) ? 'Liked' : '';
      toast('Liked!');
    });
    var marked = isMarkedUnavailable(record);
    var mark = document.createElement('button');
    mark.type = 'button';
    mark.textContent = marked ? 'Mark as available' : 'Mark as unavailable';
    mark.setAttribute('aria-pressed', marked ? 'true' : 'false');
    mark.style.cssText = 'cursor:pointer;font-size:12px;padding:4px 10px;border:1px solid ' +
      (marked ? '#2e7d32' : '#999') + ';background:#fff;color:' + (marked ? '#2e7d32' : '#555') + ';border-radius:12px;';
    mark.addEventListener('click', function () {
      animate(mark, 'shoplita-anim-save');
      var nowMarked = toggleUnavailable(record);
      mark.textContent = nowMarked ? 'Mark as available' : 'Mark as unavailable';
      mark.setAttribute('aria-pressed', nowMarked ? 'true' : 'false');
      mark.style.borderColor = nowMarked ? '#2e7d32' : '#999';
      mark.style.color = nowMarked ? '#2e7d32' : '#555';
      setTimeout(renderCompare, 400);
    });
    var viewNext = document.createElement('button');
    viewNext.type = 'button';
    viewNext.textContent = 'View next';
    viewNext.style.cssText = 'cursor:pointer;font-size:12px;padding:4px 10px;border:1px solid #777;background:#fff;color:#555;border-radius:12px;';
    viewNext.addEventListener('click', function () {
      var other = label === 'A' ? compareState.b : compareState.a;
      var candidate = nextAvailableRecord(recordItemKey(record), compareRecordKey(other));
      if (!candidate) return;
      setCompareSide(label, candidate);
      renderCompare();
    });
    var scoreLabel = document.createElement('span');
    scoreLabel.textContent = isLiked(record) ? 'Liked' : '';
    scoreLabel.style.cssText = 'color:#666;font-size:11px;';
    likeRow.appendChild(like);
    likeRow.appendChild(mark);
    likeRow.appendChild(viewNext);
    likeRow.appendChild(scoreLabel);
    col.appendChild(likeRow);

    var chips = document.createElement('div');
    chips.style.cssText = 'display:flex;gap:4px;flex-wrap:wrap;';
    for (var c = 0; c < side.options.colors.length; c++) {
      (function (color) {
        var chip = document.createElement('button');
        chip.type = 'button';
        chip.textContent = color || 'default';
        var active = color === side.color;
        chip.setAttribute('aria-pressed', active ? 'true' : 'false');
        chip.style.cssText = 'cursor:pointer;font-size:11px;padding:3px 9px;border-radius:12px;border:1px solid ' +
          (active ? '#c94f86' : '#ccc') + ';background:' + (active ? '#e6659b' : '#fff') +
          ';color:' + (active ? '#fff' : '#555') + ';';
        chip.addEventListener('click', function () {
          setCompareColor(side, color);
          renderCompare();
        });
        chips.appendChild(chip);
      })(side.options.colors[c]);
    }
    col.appendChild(chips);

    for (var t = 0; t < side.options.types.length; t++) {
      col.appendChild(renderCompareTypeRow(side, side.options.types[t]));
    }

    var subtotal = document.createElement('div');
    subtotal.style.cssText = 'margin-top:auto;padding:8px 10px;border-top:2px solid #eee;background:#fafafa;' +
      'border-radius:6px;font-weight:700;text-align:right;';
    subtotal.textContent = 'Item ' + label + ' total: ' + (record.currency ? record.currency + ' ' : '') +
      sideTotal(side).toFixed(2);
    col.appendChild(subtotal);
    return col;
  }

  function renderCompare() {
    if (!compareEl) return;
    while (compareEl.firstChild) compareEl.removeChild(compareEl.firstChild);
    var records = compareRecords();

    var win = document.createElement('div');
    win.className = 'shoplita-panel';
    win.style.cssText = 'background:#fff;color:#222;border-radius:12px;width:min(1100px,96vw);max-height:92vh;' +
      'display:flex;flex-direction:column;overflow:hidden;font:13px/1.4 sans-serif;box-shadow:0 10px 40px rgba(0,0,0,.4);';

    var head = document.createElement('div');
    head.style.cssText = 'display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid #eee;flex-wrap:wrap;';
    var heading = document.createElement('strong');
    heading.textContent = 'Compare';
    head.appendChild(heading);
    head.appendChild(makeCompareSelect('A', records, compareState.a && compareState.a.record, function (record) {
      setCompareSide('A', record);
      renderCompare();
    }));
    var vs = document.createElement('span');
    vs.textContent = 'vs';
    vs.style.cssText = 'color:#888;';
    head.appendChild(vs);
    head.appendChild(makeCompareSelect('B', records, compareState.b && compareState.b.record, function (record) {
      setCompareSide('B', record);
      renderCompare();
    }));
    var rankBtn = document.createElement('button');
    rankBtn.type = 'button';
    rankBtn.className = 'shoplita-focus';
    rankBtn.textContent = 'Rank by: ' + (compareState.rankBy === 'priority' ? 'Priority' : 'Recently added');
    rankBtn.setAttribute('aria-label', 'Toggle picker ranking');
    rankBtn.style.cssText = 'cursor:pointer;font-size:11px;padding:3px 8px;border:1px solid #999;background:#fff;color:#555;border-radius:10px;';
    rankBtn.addEventListener('click', function () {
      compareState.rankBy = compareState.rankBy === 'priority' ? 'recent' : 'priority';
      persistCompareState();
      renderCompare();
    });
    head.appendChild(rankBtn);
    var allCollections = loadCollections();
    if (allCollections.length) {
      var setFilter = document.createElement('select');
      setFilter.setAttribute('aria-label', 'Filter by set');
      setFilter.style.cssText = 'max-width:180px;padding:3px 6px;border:1px solid #ccc;border-radius:6px;font-size:12px;';
      var allOption = document.createElement('option');
      allOption.value = '';
      allOption.textContent = 'All sets';
      setFilter.appendChild(allOption);
      for (var sc = 0; sc < allCollections.length; sc++) {
        var setChoice = document.createElement('option');
        setChoice.value = allCollections[sc].id;
        setChoice.textContent = 'Set: ' + allCollections[sc].name;
        setFilter.appendChild(setChoice);
      }
      setFilter.value = compareState.filterSet || '';
      setFilter.addEventListener('change', function () {
        compareState.filterSet = setFilter.value || null;
        persistCompareState();
        renderCompare();
      });
      head.appendChild(setFilter);
    }
    var close = document.createElement('button');
    close.type = 'button';
    close.textContent = '\u00d7';
    close.setAttribute('aria-label', 'Close compare');
    close.style.cssText = 'margin-left:auto;cursor:pointer;border:none;background:none;font-size:20px;line-height:1;';
    close.addEventListener('click', closeCompare);
    head.appendChild(close);

    var body = document.createElement('div');
    body.style.cssText = 'display:flex;gap:12px;padding:12px 14px;overflow:auto;flex:1;flex-wrap:wrap;';
    body.appendChild(renderCompareSide(compareState.a, 'A'));
    body.appendChild(renderCompareSide(compareState.b, 'B'));

    var totalA = sideTotal(compareState.a);
    var totalB = sideTotal(compareState.b);
    var currencyA = (compareState.a && compareState.a.record && compareState.a.record.currency) || '';
    var currencyB = (compareState.b && compareState.b.record && compareState.b.record.currency) || '';
    var currency = currencyA || currencyB || '';
    var mixedCurrency = !!currencyA && !!currencyB && currencyA !== currencyB;
    var outfitCurrency = mixedCurrency ? '' : currency;
    var foot = document.createElement('div');
    foot.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 14px;border-top:1px solid #eee;background:#fafafa;';
    var totalEl = document.createElement('strong');
    totalEl.setAttribute('aria-live', 'polite');
    totalEl.style.cssText = 'font-size:15px;';
    totalEl.textContent = mixedCurrency
      ? 'Combined total: ' + currencyA + ' ' + totalA.toFixed(2) + ' + ' + currencyB + ' ' + totalB.toFixed(2) + ' (no conversion)'
      : 'Combined total: ' + (currency ? currency + ' ' : '') + (Math.round((totalA + totalB) * 100) / 100).toFixed(2);
    var parts = document.createElement('span');
    parts.style.cssText = 'color:#666;';
    parts.textContent = 'A ' + totalA.toFixed(2) + ' + B ' + totalB.toFixed(2);
    var saveOutfitBtn = document.createElement('button');
    saveOutfitBtn.type = 'button';
    saveOutfitBtn.textContent = 'Save outfit';
    saveOutfitBtn.style.cssText = 'cursor:pointer;font-size:12px;padding:4px 10px;border:1px solid #c94f86;background:#e6659b;color:#fff;border-radius:8px;font-weight:600;';
    saveOutfitBtn.addEventListener('click', function () {
      var pieces = collectComparePieces();
      if (!pieces.length) { toast('Nothing selected to save', true); return; }
      var name = window.prompt('Outfit name', 'Outfit ' + new Date().toISOString().slice(0, 10));
      if (!name) return;
      var outfit = createOutfit(name, pieces, outfitCurrency);
      if (!outfit) { toast('Could not save outfit', true); return; }
      if (savedPanelEl && savedPanelEl.style.display !== 'none') renderOutfitsBar();
      toast('Saved outfit "' + outfit.name + '" (' + pieces.length + ' pieces, ' + outfit.total.toFixed(2) + ')');
    });
    var footRight = document.createElement('div');
    footRight.style.cssText = 'display:flex;align-items:center;gap:10px;';
    footRight.appendChild(parts);
    footRight.appendChild(saveOutfitBtn);
    foot.appendChild(totalEl);
    foot.appendChild(footRight);

    win.appendChild(head);
    win.appendChild(body);
    win.appendChild(foot);
    compareEl.appendChild(win);
  }

  function openComparePanel() {
    if (!compareEl) {
      compareEl = document.createElement('div');
      compareEl.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.5);z-index:999999;' +
        'display:flex;align-items:center;justify-content:center;';
      compareEl.addEventListener('click', function (event) {
        if (event.target === compareEl) closeCompare();
      });
      document.body.appendChild(compareEl);
    }
    compareEl.style.display = 'flex';
    restoreCompareState();
    renderCompare();
  }

  function variantCount(products) {
    var n = 0;
    for (var i = 0; i < products.length; i++) n += products[i].variants.length;
    return n;
  }

  var toastEl = null;
  var toastTimer = null;

  function toast(message, isError) {
    if (!toastEl) {
      toastEl = document.createElement('div');
      toastEl.style.cssText =
        'position:fixed;right:16px;bottom:130px;z-index:999999;max-width:min(340px,calc(100vw - 32px));' +
        'padding:10px 14px;border-radius:8px;font:13px/1.4 sans-serif;' +
        'color:#fff;background:#333;box-shadow:0 2px 10px rgba(0,0,0,.3);' +
        'opacity:0;transition:opacity .2s;pointer-events:none;';
      toastEl.setAttribute('role', 'status');
      toastEl.setAttribute('aria-live', 'polite');
      document.body.appendChild(toastEl);
    }
    toastEl.textContent = message;
    toastEl.style.background = isError ? '#b3261e' : '#333';
    toastEl.style.opacity = '1';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      toastEl.style.opacity = '0';
    }, 3500);
  }

  function exportAll(all) {
    var stamp = new Date().toISOString().slice(0, 10);
    var setRows = buildSetRows(all);
    var text = JSON.stringify({
      exportedAt: new Date().toISOString(),
      count: all.length,
      setCount: setRows.length,
      setRows: setRows,
      priority: loadPriority(),
      unavailable: loadUnavailable(),
      collections: loadCollections(),
      outfits: loadOutfits(),
      products: all
    }, null, 2);
    if (download('shoplita-saved-info-' + stamp + '.json', text)) {
      toast('Downloaded ' + all.length + ' product(s)');
    } else {
      copyText(text).then(function () {
        toast('Download not supported, copied JSON to clipboard instead');
      });
    }
  }

  function exportForUserscript(all) {
    var stamp = new Date().toISOString().slice(0, 10);
    var text = JSON.stringify({
      format: 'shoplita',
      version: 2,
      exportedAt: new Date().toISOString(),
      priority: loadPriority(),
      unavailable: loadUnavailable(),
      collections: loadCollections(),
      outfits: loadOutfits(),
      products: all
    }, null, 2);
    if (download('shoplita-share-' + stamp + '.json', text)) {
      toast('Exported ' + all.length + ' snapshot(s) for another userscript user');
    } else {
      copyText(text).then(function () {
        toast('Download not supported, copied share JSON to clipboard instead');
      });
    }
  }

  function ensureStyles() {
    try {
      if (document.getElementById && document.getElementById('shoplita-saveinfo-styles')) return;
      var style = document.createElement('style');
      style.id = 'shoplita-saveinfo-styles';
      style.textContent =
        '@keyframes shoplita-pop { 0% { transform: scale(1); } 40% { transform: scale(1.14); } 100% { transform: scale(1); } }' +
        '@keyframes shoplita-like { 0% { transform: scale(1); } 35% { transform: scale(1.25); } 100% { transform: scale(1); } }' +
        '.shoplita-anim-save { animation: shoplita-pop .35s ease; }' +
        '.shoplita-anim-like { animation: shoplita-like .45s ease; }' +
        '.shoplita-focus:focus-visible { outline: 2px solid #c94f86; outline-offset: 2px; }' +
        '.shoplita-panel button:focus-visible, .shoplita-panel a:focus-visible, .shoplita-panel input:focus-visible, .shoplita-panel select:focus-visible { outline: 2px solid #c94f86; outline-offset: 2px; }' +
        '@media (prefers-reduced-motion: reduce) { .shoplita-anim-save, .shoplita-anim-like { animation: none; } }';
      (document.head || document.documentElement || document.body).appendChild(style);
    } catch (e) {}
  }

  function animate(el, className) {
    if (!el || !el.classList) return;
    el.classList.remove(className);
    void el.offsetWidth;
    el.classList.add(className);
  }

  var refreshStatus = null;

  function buildUi() {
    ensureStyles();
    normalizeSources();
    var panel = document.createElement('div');
    panel.className = 'shoplita-panel';
    panel.style.cssText =
      'position:fixed;right:16px;bottom:16px;z-index:999999;display:flex;' +
      'flex-direction:column;gap:6px;align-items:flex-end;font:13px/1.4 sans-serif;' +
      'max-height:calc(100vh - 32px);overflow-y:auto;max-width:calc(100vw - 32px);';

    function makeButton(label, primary, compact) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'shoplita-focus';
      b.textContent = label;
      b.style.cssText =
        'cursor:pointer;border:1px solid ' + (primary ? '#c94f86' : '#999') + ';' +
        'border-radius:8px;padding:' + (primary ? '10px 18px' : (compact ? '4px 10px' : '6px 12px')) + ';' +
        'font-size:' + (primary ? '14px' : (compact ? '11px' : '12px')) + ';font-weight:600;color:#fff;' +
        'background:' + (primary ? '#e6659b' : '#777') + ';' +
        'box-shadow:0 2px 6px rgba(0,0,0,.25);';
      b.addEventListener('mouseenter', function () {
        b.style.filter = 'brightness(1.08)';
      });
      b.addEventListener('mouseleave', function () {
        b.style.filter = '';
      });
      return b;
    }

    var saveBtn = makeButton('Save listing', true);
    var likePageBtn = makeButton('I like this!', false);
    var copyAllBtn = makeButton('Copy variants (TSV)', false);
    var downloadBtn = makeButton('Download JSON backup', false);
    var copySetsBtn = makeButton('Copy history (TSV)', false);
    var csvBtn = makeButton('Download history (CSV)', false);
    var copyWishlistBtn = makeButton('Copy wishlist (TSV)', false);
    var wishlistBtn = makeButton('Download wishlist (CSV)', false);
    var copyPriceHistoryBtn = makeButton('Copy price history (TSV)', false);
    var priceHistoryCsvBtn = makeButton('Download price history (CSV)', false);
    var shareBtn = makeButton('Export for userscript', false);
    var importBtn = makeButton('Import data', false);
    var savedBtn = makeButton('Saved items', false, true);
    var compareBtn = makeButton('Compare', false, true);
    var moreBtn = makeButton('More\u2026', false, true);
    moreBtn.setAttribute('aria-expanded', 'false');
    moreBtn.setAttribute('aria-controls', 'shoplita-more-menu');

    var onProductPage = !!adapterFor(location.href);
    if (!onProductPage) {
      saveBtn.disabled = true;
      likePageBtn.disabled = true;
      saveBtn.title = 'Open a product listing to save it';
      likePageBtn.title = 'Open a product listing to like it';
      saveBtn.style.opacity = '0.55';
      likePageBtn.style.opacity = '0.55';
    } else {
      var pageHandle = currentPageId();
      var latest = findLatestByHandle(pageHandle);
      var today = new Date().toISOString().slice(0, 10);
      if (latest && String(latest.savedAt || '').slice(0, 10) === today) {
        saveBtn.textContent = 'Saved';
        saveBtn.title = 'Click to refresh this saved listing';
      }
      if (pageHandle && priorityScore({ handle: pageHandle, source: currentSource() }) > 0) {
        likePageBtn.textContent = 'Liked';
        likePageBtn.disabled = true;
      }
    }

    var status = document.createElement('span');
    status.style.cssText =
      'background:rgba(0,0,0,.65);color:#fff;padding:3px 8px;border-radius:6px;font-size:11px;';
    status.setAttribute('role', 'status');
    status.setAttribute('aria-live', 'polite');

    var minBtn = document.createElement('button');
    minBtn.type = 'button';
    minBtn.textContent = '\u2212';
    minBtn.className = 'shoplita-focus';
    minBtn.setAttribute('aria-label', 'Minimize panel');
    minBtn.setAttribute('title', 'Minimize');
    minBtn.style.cssText = 'cursor:pointer;border:1px solid #999;background:#777;color:#fff;border-radius:6px;padding:2px 9px;font-weight:700;line-height:1;';

    var miniBtn = document.createElement('button');
    miniBtn.type = 'button';
    miniBtn.textContent = '+';
    miniBtn.className = 'shoplita-focus';
    miniBtn.setAttribute('aria-label', 'Show Shoplita tools');
    miniBtn.setAttribute('title', 'Show Shoplita tools');
    miniBtn.style.cssText = 'display:none;position:fixed;right:16px;bottom:16px;z-index:999999;width:42px;height:42px;' +
      'border-radius:50%;border:1px solid #c94f86;background:#e6659b;color:#fff;font-size:20px;font-weight:700;' +
      'cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,.3);align-items:center;justify-content:center;';

    function setMinimized(minimized) {
      panel.style.display = minimized ? 'none' : 'flex';
      miniBtn.style.display = minimized ? 'flex' : 'none';
      var ui = loadUi();
      ui.minimized = !!minimized;
      saveUi(ui);
    }
    minBtn.addEventListener('click', function () { setMinimized(true); });
    miniBtn.addEventListener('click', function () { setMinimized(false); });

    refreshStatus = function () {
      var all = loadAll();
      var setCount = buildSetRows(all).length;
      var full = all.length + ' snapshot(s), ' + variantCount(all) + ' variant(s), ' + setCount + ' set row(s)';
      status.textContent = all.length + ' items \u00b7 ' + setCount + ' sets';
      status.title = full;
      status.setAttribute('aria-label', full);
      if (savedPanelEl && savedPanelEl.style.display !== 'none') renderSavedPanel();
    };

    var topRow = document.createElement('div');
    topRow.style.cssText = 'display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end;';
    topRow.appendChild(saveBtn);
    topRow.appendChild(likePageBtn);

    var secondaryRow = document.createElement('div');
    secondaryRow.style.cssText = 'display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end;';
    secondaryRow.appendChild(savedBtn);
    secondaryRow.appendChild(compareBtn);
    secondaryRow.appendChild(moreBtn);

    var moreBox = document.createElement('div');
    moreBox.id = 'shoplita-more-menu';
    moreBox.style.cssText = 'display:none;flex-direction:column;gap:6px;padding:8px;border:1px solid #ccc;border-radius:8px;background:rgba(255,255,255,.96);';
    moreBox.setAttribute('role', 'group');
    moreBox.setAttribute('aria-label', 'More options');

    var importRow = document.createElement('div');
    importRow.style.cssText = 'display:flex;gap:6px;flex-wrap:wrap;';
    importRow.appendChild(importBtn);

    var exportLabel = document.createElement('div');
    exportLabel.textContent = 'Export';
    exportLabel.style.cssText = 'font-size:10px;font-weight:700;color:#666;text-transform:uppercase;letter-spacing:.5px;';

    var row = document.createElement('div');
    row.style.cssText = 'display:flex;gap:6px;flex-wrap:wrap;';
    row.appendChild(copyAllBtn);
    row.appendChild(downloadBtn);
    var row2 = document.createElement('div');
    row2.style.cssText = 'display:flex;gap:6px;flex-wrap:wrap;';
    row2.appendChild(copySetsBtn);
    row2.appendChild(csvBtn);
    var row3 = document.createElement('div');
    row3.style.cssText = 'display:flex;gap:6px;flex-wrap:wrap;';
    row3.appendChild(copyWishlistBtn);
    row3.appendChild(wishlistBtn);
    var row4 = document.createElement('div');
    row4.style.cssText = 'display:flex;gap:6px;flex-wrap:wrap;';
    row4.appendChild(shareBtn);
    var row5 = document.createElement('div');
    row5.style.cssText = 'display:flex;gap:6px;flex-wrap:wrap;';
    row5.appendChild(copyPriceHistoryBtn);
    row5.appendChild(priceHistoryCsvBtn);
    moreBox.appendChild(importRow);
    moreBox.appendChild(exportLabel);
    moreBox.appendChild(row);
    moreBox.appendChild(row2);
    moreBox.appendChild(row3);
    moreBox.appendChild(row4);
    moreBox.appendChild(row5);

    var statusRow = document.createElement('div');
    statusRow.style.cssText = 'display:flex;align-items:center;gap:6px;';
    statusRow.appendChild(status);
    statusRow.appendChild(minBtn);

    panel.appendChild(topRow);
    panel.appendChild(secondaryRow);
    panel.appendChild(moreBox);
    panel.appendChild(statusRow);
    document.body.appendChild(panel);
    document.body.appendChild(miniBtn);
    if (loadUi().minimized) setMinimized(true);
    refreshStatus();
    updateDebugAttribute();

    function setMoreOpen(open) {
      moreBox.style.display = open ? 'flex' : 'none';
      moreBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
    }
    moreBtn.addEventListener('click', function () {
      setMoreOpen(moreBox.style.display !== 'flex');
    });
    moreBox.addEventListener('click', function (event) {
      if (event && event.target && event.target.tagName === 'BUTTON') setMoreOpen(false);
    });

    saveBtn.addEventListener('click', function () {
      animate(saveBtn, 'shoplita-anim-save');
      saveBtn.disabled = true;
      saveBtn.textContent = 'Saving...';
      collectProduct().then(function (record) {
        upsertRecord(record);
        var target = findCollection(getDefaultSetId());
        if (target) addCollectionItem(target.id, recordItemKey(record));
        refreshStatus();
        saveBtn.textContent = 'Saved';
        toast(target ? 'Saved to "' + target.name + '"!' : 'Saved!');
      }).catch(function (e) {
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save listing';
        toast('Save failed: ' + (e && e.message ? e.message : e), true);
      });
    });

    likePageBtn.addEventListener('click', function () {
      animate(likePageBtn, 'shoplita-anim-like');
      likePageBtn.disabled = true;
      collectProduct().then(function (record) {
        upsertRecord(record);
        likeItem(record);
        var likeTarget = findCollection(getDefaultSetId());
        if (likeTarget) addCollectionItem(likeTarget.id, recordItemKey(record));
        refreshStatus();
        likePageBtn.textContent = 'Liked';
        toast(likeTarget ? 'Liked! Saved to "' + likeTarget.name + '"' : 'Liked!');
      }).catch(function (e) {
        likePageBtn.disabled = false;
        likePageBtn.textContent = 'I like this!';
        toast('Like failed: ' + (e && e.message ? e.message : e), true);
      });
    });

    shareBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      exportForUserscript(all);
    });

    copyAllBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      copyText(toTsv(all)).then(function (ok) {
        toast(ok ? 'Copied ' + variantCount(all) + ' rows (TSV) to clipboard' : 'Copy failed', !ok);
      });
    });

    downloadBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      exportAll(all);
    });

    copySetsBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      var matrix = setMatrix(all);
      copyText(toSetTsv(all)).then(function (ok) {
        toast(ok ? 'Copied ' + matrix.rows.length + ' history row(s) (TSV) to clipboard' : 'Copy failed', !ok);
      });
    });

    csvBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      var matrix = setMatrix(all);
      if (downloadSetsCsv(all)) {
        toast('Downloaded ' + matrix.rows.length + ' history row(s) as CSV');
      } else {
        toast('CSV download failed', true);
      }
    });

    copyWishlistBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      var matrix = summaryMatrix(all);
      copyText(toSummaryTsv(all)).then(function (ok) {
        toast(ok ? 'Copied ' + matrix.rows.length + ' wishlist row(s) (TSV) to clipboard' : 'Copy failed', !ok);
      });
    });

    wishlistBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      var matrix = summaryMatrix(all);
      if (downloadSummaryCsv(all)) {
        toast('Downloaded ' + matrix.rows.length + ' wishlist row(s) as CSV');
      } else {
        toast('CSV download failed', true);
      }
    });

    copyPriceHistoryBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      var matrix = historyMatrix(all);
      copyText(toHistoryTsv(all)).then(function (ok) {
        toast(ok ? 'Copied ' + matrix.rows.length + ' price history row(s) (TSV)' : 'Copy failed', !ok);
      });
    });

    priceHistoryCsvBtn.addEventListener('click', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      var matrix = historyMatrix(all);
      if (downloadPriceHistoryCsv(all)) {
        toast('Downloaded ' + matrix.rows.length + ' price history row(s) as CSV');
      } else {
        toast('CSV download failed', true);
      }
    });

    savedBtn.addEventListener('click', function () {
      toggleSavedPanel();
    });

    compareBtn.addEventListener('click', function () {
      openComparePanel();
    });

    importBtn.addEventListener('click', function () {
      pickImportFile(function (text) {
        var result = mergeImport(text);
        if (result.error) { toast('Import failed: ' + result.error, true); return; }
        refreshStatus();
        toast('Imported: ' + result.added + ' new, ' + result.updated + ' updated, ' + result.skipped + ' skipped');
      });
    });
  }

  function whenBodyReady(fn) {
    if (document.body) { fn(); return; }
    var done = false;
    function run() {
      if (done || !document.body) return;
      done = true;
      fn();
    }
    document.addEventListener('DOMContentLoaded', run, false);
    var tries = 0;
    var timer = setInterval(function () {
      if (document.body || ++tries > 200) {
        clearInterval(timer);
        run();
      }
    }, 50);
  }

  migrateLegacyKeys();
  installAliExpressSniffer();
  whenBodyReady(buildUi);

  if (typeof GM_registerMenuCommand === 'function') {
    GM_registerMenuCommand('Download saved info (JSON)', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      exportAll(all);
    });
    GM_registerMenuCommand('Copy saved info (TSV)', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      copyText(toTsv(all)).then(function (ok) {
        toast(ok ? 'Copied TSV to clipboard' : 'Copy failed', !ok);
      });
    });
    GM_registerMenuCommand('Copy history (TSV)', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      copyText(toSetTsv(all)).then(function (ok) {
        toast(ok ? 'Copied history (TSV) to clipboard' : 'Copy failed', !ok);
      });
    });
    GM_registerMenuCommand('Download history (CSV)', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      if (downloadSetsCsv(all)) toast('Downloaded history as CSV');
      else toast('CSV download failed', true);
    });
    GM_registerMenuCommand('Copy wishlist (TSV)', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      copyText(toSummaryTsv(all)).then(function (ok) {
        toast(ok ? 'Copied wishlist (TSV) to clipboard' : 'Copy failed', !ok);
      });
    });
    GM_registerMenuCommand('Download wishlist (CSV)', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      if (downloadSummaryCsv(all)) toast('Downloaded wishlist as CSV');
      else toast('CSV download failed', true);
    });
    GM_registerMenuCommand('Download price history (CSV)', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      if (downloadPriceHistoryCsv(all)) toast('Downloaded price history as CSV');
      else toast('CSV download failed', true);
    });
    GM_registerMenuCommand('Export for userscript', function () {
      var all = loadAll();
      if (!all.length) { toast('Nothing saved yet', true); return; }
      exportForUserscript(all);
    });
    GM_registerMenuCommand('Import data', function () {
      pickImportFile(function (text) {
        var result = mergeImport(text);
        if (result.error) { toast('Import failed: ' + result.error, true); return; }
        if (refreshStatus) refreshStatus();
        toast('Imported: ' + result.added + ' new, ' + result.updated + ' updated, ' + result.skipped + ' skipped');
      });
    });
    GM_registerMenuCommand('Clear saved info', function () {
      if (!confirm('Delete all saved Shoplita product info, priority scores and availability marks?')) return;
      saveAll([]);
      savePriority({});
      saveUnavailable({});
      compareState.a = null;
      compareState.b = null;
      persistCompareState();
      if (refreshStatus) refreshStatus();
      toast('Cleared saved info');
    });
  }

  try {
    if (typeof window !== 'undefined') {
      window.__shoplita = {
        version: (typeof GM_info !== 'undefined' && GM_info.script) ? GM_info.script.version : '',
        adapter: function () {
          var found = adapterFor(location.href);
          return found ? found.id : null;
        },
        capturedData: getCapturedAliExpressData,
        capturedImages: getCapturedAliExpressImages,
        domImages: aliexpressDomImages
      };
    }
  } catch (e) {}

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      classify: classify,
      normalize: normalize,
      currentHandle: currentHandle,
      currentPageId: currentPageId,
      adapterFor: adapterFor,
      findLatestByHandle: findLatestByHandle,
      loadAll: loadAll,
      recordKey: recordKey,
      listingKeys: listingKeys,
      recordsMatch: recordsMatch,
      dedupeList: dedupeList,
      dedupeRecords: dedupeRecords,
      upsertRecord: upsertRecord,
      collapseListingRows: collapseListingRows,
      recordItemKey: recordItemKey,
      loadPriority: loadPriority,
      priorityScore: priorityScore,
      isLiked: isLiked,
      likeItem: likeItem,
      variantPriceRange: variantPriceRange,
      compareRecords: compareRecords,
      loadUnavailable: loadUnavailable,
      isMarkedUnavailable: isMarkedUnavailable,
      toggleUnavailable: toggleUnavailable,
      loadCollections: loadCollections,
      saveCollections: saveCollections,
      createCollection: createCollection,
      deleteCollection: deleteCollection,
      addCollectionItem: addCollectionItem,
      getDefaultSetId: getDefaultSetId,
      setDefaultSetId: setDefaultSetId,
      getSortBy: getSortBy,
      setSortBy: setSortBy,
      toggleCollectionItem: toggleCollectionItem,
      collectionsForItem: collectionsForItem,
      collectionRecord: collectionRecord,
      loadOutfits: loadOutfits,
      saveOutfits: saveOutfits,
      createOutfit: createOutfit,
      deleteOutfit: deleteOutfit,
      outfitRecord: outfitRecord,
      collectComparePieces: collectComparePieces,
      aliexpressSkuBase: aliexpressSkuBase,
      aliexpressVariantOptions: aliexpressVariantOptions,
      aliexpressAvailability: aliexpressAvailability,
      aliexpressDomVariants: aliexpressDomVariants,
      aliexpressImageUrl: aliexpressImageUrl,
      captureAliExpressText: captureAliExpressText,
      getCapturedAliExpressData: getCapturedAliExpressData,
      getCapturedAliExpressImages: getCapturedAliExpressImages,
      aliexpressDomImages: aliexpressDomImages,
      findSkuBaseObject: findSkuBaseObject,
      findImageList: findImageList,
      collectImages: collectImages,
      compareOrder: compareOrder,
      nextAvailableRecord: nextAvailableRecord,
      loadCompareKeys: loadCompareKeys,
      persistCompareState: persistCompareState,
      restoreCompareState: restoreCompareState,
      exportForUserscript: exportForUserscript,
      loadUi: loadUi,
      saveUi: saveUi,
      removeItemGroup: removeItemGroup,
      mergeImport: mergeImport,
      variantPieces: variantPieces,
      buildSetRows: buildSetRows,
      setMatrix: setMatrix,
      latestSnapshots: latestSnapshots,
      buildSummaryRows: buildSummaryRows,
      summaryMatrix: summaryMatrix,
      historyMatrix: historyMatrix,
      toHistoryTsv: toHistoryTsv,
      compareOptions: compareOptions,
      newCompareSide: newCompareSide,
      setCompareColor: setCompareColor,
      sideTotal: sideTotal,
      compareAddByHandle: compareAddByHandle,
      toTsv: toTsv,
      toSetTsv: toSetTsv,
      toSummaryTsv: toSummaryTsv,
      toCsv: toCsv
    };
  }
})();

