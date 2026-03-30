# MindMap POC 仕様書

**バージョン**: 0.1.0
**対象フェーズ**: POC（ブラウザのみ）
**技術スタック**: Rust (WASM) + TypeScript/Svelte 5

---

## 1. 概要

### 1.1 目的

ブラウザ上で動作するマインドマップ作成ツールのPOCを構築する。text-to-diagram機能は持たず、GUIによる直接編集を主体とする。Rustコアを WASM にコンパイルし、ドキュメントモデル・レイアウト計算・SVG生成をWASM側に集約する。

### 1.2 スコープ（POC）

| 対象 | 内容 |
|------|------|
| ✅ 含む | ノード追加・編集・削除、放射状レイアウト、SVGレンダリング、JSON保存/読込、ズーム・パン、ドラッグ移動、Undo/Redo |
| ❌ 含まない | CLIツール、デスクトップアプリ、サーバーサイド、コラボレーション、画像エクスポート |

---

## 2. ファイル・ディレクトリ構成

```
mindmap/
├── rust-core/                  # Rust/WASMプロジェクト
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs              # wasm-bindgen エントリポイント
│       ├── model.rs            # データ構造定義
│       ├── layout.rs           # 放射状レイアウトアルゴリズム
│       ├── renderer.rs         # SVG文字列生成
│       └── serializer.rs       # JSON シリアライズ/デシリアライズ
│
├── frontend/                   # Svelte 5 プロジェクト
│   ├── package.json
│   ├── vite.config.ts
│   ├── tsconfig.json
│   └── src/
│       ├── main.ts             # エントリポイント
│       ├── App.svelte          # ルートコンポーネント
│       ├── lib/
│       │   ├── wasm.ts         # WASMラッパー（初期化・型定義）
│       │   ├── interaction.ts  # 座標変換・ドラッグ・ズームロジック
│       │   └── fileio.ts       # ファイル保存・読込
│       └── components/
│           ├── Toolbar.svelte
│           ├── Canvas.svelte   # SVG表示・イベントハンドリング
│           ├── StatusBar.svelte
│           └── ContextMenu.svelte
│
└── build.sh                    # wasm-pack build → frontend/src/lib/wasm/ にコピー
```

---

## 3. データモデル

### 3.1 Rust 側定義（`model.rs`）

```rust
use serde::{Serialize, Deserialize};
use std::collections::HashMap;

pub type NodeId = String;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Node {
    pub id: NodeId,
    pub text: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub color: String,          // ブランチカラー（継承）
    pub parent_id: Option<NodeId>,
    pub children_ids: Vec<NodeId>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MindMap {
    pub version: u32,           // スキーマバージョン（現在: 1）
    pub name: String,
    pub root_id: NodeId,
    pub nodes: HashMap<NodeId, Node>,
}
```

### 3.2 JSON 保存フォーマット

```json
{
  "version": 1,
  "name": "プロジェクト計画",
  "root_id": "node-root",
  "nodes": {
    "node-root": {
      "id": "node-root",
      "text": "プロジェクト計画",
      "x": 600.0,
      "y": 400.0,
      "width": 160.0,
      "height": 52.0,
      "color": "#667eea",
      "parent_id": null,
      "children_ids": ["node-abc", "node-def"]
    },
    "node-abc": {
      "id": "node-abc",
      "text": "フロントエンド",
      "x": 380.0,
      "y": 260.0,
      "width": 140.0,
      "height": 40.0,
      "color": "#f093fb",
      "parent_id": "node-root",
      "children_ids": []
    }
  }
}
```

**設計方針**:
- ファイル拡張子: `.json`（将来的に `.mindmap.json` も検討）
- `x`, `y` はノード中心座標
- `color` はルートの子ノード単位で割り当て、子孫は継承
- `version` フィールドで将来のスキーマ移行に対応

---

## 4. WASM API 定義

### 4.1 公開インターフェース（`lib.rs`）

```rust
#[wasm_bindgen]
pub struct MindMapEngine { inner: MindMap }

#[wasm_bindgen]
impl MindMapEngine {

    // --- ライフサイクル ---
    #[wasm_bindgen(constructor)]
    pub fn new(name: &str, root_text: &str) -> MindMapEngine;

    // --- シリアライズ ---
    /// MindMap全体をJSON文字列にシリアライズ
    pub fn to_json(&self) -> Result<String, JsValue>;
    /// JSON文字列からMindMapEngineを生成
    pub fn from_json(json: &str) -> Result<MindMapEngine, JsValue>;

    // --- ノード操作 ---
    /// 子ノードを追加し、新しいNodeIdを返す
    pub fn add_child(&mut self, parent_id: &str, text: &str) -> Option<String>;
    /// ノードとその子孫を再帰削除。ルートノードは削除不可
    pub fn remove_node(&mut self, node_id: &str) -> bool;
    /// ノードのテキストを更新
    pub fn update_text(&mut self, node_id: &str, text: &str) -> bool;
    /// ノードの座標を更新（ドラッグ移動）
    pub fn update_position(&mut self, node_id: &str, x: f64, y: f64) -> bool;

    // --- レイアウト ---
    /// 放射状レイアウトを実行し、全ノードの座標を更新
    pub fn auto_layout(&mut self);

    // --- レンダリング ---
    /// 現在の状態をSVG文字列として返す
    pub fn render_svg(&self) -> String;

    // --- クエリ ---
    /// ノード数を返す
    pub fn node_count(&self) -> usize;
    /// ルートノードIDを返す
    pub fn root_id(&self) -> String;
}
```

### 4.2 TypeScript 側の型定義（`wasm.ts` で管理）

```typescript
// wasm-bindgenが自動生成するが、利便性のためラッパーを定義
export interface NodeData {
  id: string;
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
  color: string;
  parent_id: string | null;
  children_ids: string[];
}

export interface MindMapData {
  version: number;
  name: string;
  root_id: string;
  nodes: Record<string, NodeData>;
}

// WASMモジュールの初期化
export async function initWasm(): Promise<void>;

// エンジンインスタンスをシングルトンで管理
export function getEngine(): MindMapEngine;
```

---

## 5. WASM と Svelte の責務分担

POCの設計における最重要の境界線。**「計算・データ = WASM」「表示・操作 = Svelte」** を原則とする。

### 5.1 責務マトリクス

| 処理 | WASM (Rust) | Svelte (TypeScript) |
|------|------------|---------------------|
| ノードデータの保持 | ✅ `MindMap` 構造体 | ❌（コピーしない） |
| ノードの追加・削除・更新 | ✅ `add_child` / `remove_node` など | ❌ |
| 放射状レイアウト計算 | ✅ `auto_layout` | ❌ |
| テキスト幅の推定 | ✅ 文字種別ルックアップテーブル | ❌ |
| SVG文字列の生成 | ✅ `render_svg` | ❌ |
| JSON シリアライズ | ✅ `to_json` / `from_json` | ❌ |
| DOMイベントの受信 | ❌ | ✅ click / dblclick / mousemove など |
| SVGのDOM挿入 | ❌ | ✅ `{@html svgContent}` |
| ノード選択状態の保持 | ❌ | ✅ `$state(selectedId)` |
| ズーム・パン状態 | ❌ | ✅ `$state(viewBox)` |
| ドラッグ中の座標変換 | ❌ | ✅ `screenToSVG()` |
| インライン編集UI | ❌ | ✅ `<input>` オーバーレイ |
| ファイルダウンロード | ❌ | ✅ Blob + `URL.createObjectURL` |
| ファイル読込 | ❌ | ✅ FileReader API |

### 5.2 データフロー

```
[ユーザー操作]
     │
     ▼ DOMイベント
[Svelte: Canvas.svelte]
     │ スクリーン座標 → SVG座標変換
     │ 選択ノードID の特定（data-node-id属性）
     ▼
[WASMエンジン呼び出し]  ← 唯一のデータ変更経路
  engine.add_child()
  engine.update_text()
  engine.update_position()
     │
     ▼ SVG文字列
[Svelte: $derived で再計算]
  svgContent = engine.render_svg()
     │
     ▼ {@html svgContent}
[DOM に反映]
```

### 5.3 状態管理の設計（`App.svelte`）

```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  import { initWasm, getEngine } from '$lib/wasm';

  // --- WASM側が正とするデータ ---
  // Svelte側はキャッシュを持たず、常にWASMから取得する

  // --- Svelte側のUI状態 ---
  let ready = $state(false);
  let renderTick = $state(0);          // SVG再描画トリガー
  let selectedId = $state<string | null>(null);
  let viewBox = $state({ x: 0, y: 0, w: 1200, h: 800 });

  // --- SVGはrenderTickが変わるたびに再取得 ---
  let svgContent = $derived.by(() => {
    void renderTick;
    return ready ? getEngine().render_svg() : '';
  });

  // WASMを更新した後は必ずこれを呼ぶ
  function invalidate() { renderTick++; }

  onMount(async () => {
    await initWasm();
    ready = true;
  });
</script>
```

### 5.4 WASM呼び出しのルール

- **ルール1**: WASMエンジンの状態を変更する処理は、必ず `invalidate()` を末尾で呼ぶ
- **ルール2**: SVGノードのヒットテストは `data-node-id` 属性で行い、`event.target.closest('[data-node-id]')` で取得する
- **ルール3**: JS↔WASM間のデータ交換は**JSON文字列経由**を基本とし、頻繁に呼ぶ操作（`update_position`）のみプリミティブ型の引数を使う
- **ルール4**: WASM関数が `Result<_, JsValue>` を返す場合は `try/catch` で必ずハンドリングする

---

## 6. コンポーネント設計

### 6.1 コンポーネントツリー

```
App.svelte
├── Toolbar.svelte         props: selectedId, onAdd, onDelete, onSave, onLoad
├── Canvas.svelte          props: svgContent, viewBox, onNodeSelect, onNodeDblClick, onViewBoxChange
│   └── （SVGをDOMに挿入。イベントをAppに通知）
├── ContextMenu.svelte     props: visible, x, y, onAdd, onEdit, onDelete
└── StatusBar.svelte       props: nodeCount, selectedText
```

### 6.2 Canvas.svelte の詳細

Canvas は最もロジックが集中するコンポーネント。以下の処理を担当する。

**イベント処理**:
- `mousedown` on node → 選択 + ドラッグ開始
- `mousedown` on background → パン開始 + 選択解除
- `dblclick` on node → 編集オーバーレイ表示（親に通知）
- `contextmenu` on node → コンテキストメニュー表示
- `wheel` → ズーム（カーソル中心）

**座標変換（`interaction.ts`）**:

```typescript
export function screenToSVG(
  clientX: number,
  clientY: number,
  viewBox: ViewBox,
  canvasRect: DOMRect
): { x: number; y: number } {
  return {
    x: viewBox.x + (clientX - canvasRect.left) * (viewBox.w / canvasRect.width),
    y: viewBox.y + (clientY - canvasRect.top)  * (viewBox.h / canvasRect.height),
  };
}

export function zoomAtPoint(
  viewBox: ViewBox,
  factor: number,
  pivotX: number,   // スクリーン座標
  pivotY: number,
  canvasRect: DOMRect
): ViewBox {
  const svg = screenToSVG(pivotX, pivotY, viewBox, canvasRect);
  const newW = viewBox.w / factor;
  const newH = viewBox.h / factor;
  return {
    x: svg.x - (svg.x - viewBox.x) / factor,
    y: svg.y - (svg.y - viewBox.y) / factor,
    w: newW,
    h: newH,
  };
}
```

---

## 7. レイアウトアルゴリズム仕様

### 7.1 放射状レイアウト（`layout.rs`）

ルートノードを中心に、子孫ノードを放射状に配置する。

**パラメータ**:

| パラメータ | デフォルト値 | 説明 |
|-----------|------------|------|
| `center_x` | 600.0 | ルートのX座標 |
| `center_y` | 400.0 | ルートのY座標 |
| `radius_step` | 200.0 | 階層ごとの半径増分 |
| `min_angle_gap` | 0.3 rad | 隣接ノード間の最小角度間隔 |

**アルゴリズム**:

1. 各ノードのリーフ数を再帰的に計算（`count_leaves`）
2. ルートの子ノードに 2π をリーフ数比で分配
3. 各子の割り当て角度範囲の中点を配置角度 θ とし、`(center + r·cosθ, center + r·sinθ)` で座標を決定
4. 再帰的に子孫も同様に処理（角度範囲は親から引き継ぎ）

**テキスト幅推定**（サーバーなしでの近似）:

```rust
fn estimate_char_width(c: char, font_size: f64) -> f64 {
    let ratio = match c {
        'i' | 'l' | '|' | '!' | '.' | ',' => 0.30,
        'r' | 'f' | 't' => 0.45,
        'a'..='z' => 0.55,
        'A'..='Z' => 0.65,
        '0'..='9' => 0.60,
        '\u{3000}'..='\u{9FFF}' | '\u{FF00}'..='\u{FFEF}' => 1.0, // CJK
        _ => 0.60,
    };
    font_size * ratio
}

pub fn estimate_node_size(text: &str, font_size: f64) -> (f64, f64) {
    let w: f64 = text.chars().map(|c| estimate_char_width(c, font_size)).sum();
    let width = (w + 48.0).max(80.0).min(240.0); // パディング24px × 2
    let height = font_size + 26.0;
    (width, height)
}
```

---

## 8. SVGレンダリング仕様

### 8.1 ノード描画（`renderer.rs`）

`format!()` マクロによる手動SVG文字列生成。

```rust
fn render_node(n: &Node, is_root: bool, is_selected: bool) -> String {
    let (rx, ry) = (n.x - n.w / 2.0, n.y - n.h / 2.0);
    let fill = if is_root { n.color.clone() } else { hex_with_alpha(&n.color, 0.18) };
    let stroke_w = if is_root { 0.0 } else { 1.5 };
    let font_size = if is_root { 15 } else { 13 };
    let font_weight = if is_root { 700 } else { 500 };
    let text_color = if is_root { "#ffffff" } else { "#e2e8f0" };

    let selection_ring = if is_selected {
        format!(r#"<rect x="{}" y="{}" width="{}" height="{}" rx="14"
            fill="none" stroke="{}" stroke-width="2.5" opacity="0.7"/>"#,
            rx - 4.0, ry - 4.0, n.w + 8.0, n.h + 8.0, n.color)
    } else { String::new() };

    format!(r#"<g transform="translate({rx},{ry})" data-node-id="{id}" cursor="pointer">
        {selection_ring}
        <rect width="{w}" height="{h}" rx="10"
            fill="{fill}" stroke="{color}" stroke-width="{stroke_w}"/>
        <text x="{tx}" y="{ty}" text-anchor="middle" dominant-baseline="middle"
            fill="{text_color}" font-size="{font_size}" font-weight="{font_weight}"
            font-family="system-ui,sans-serif" pointer-events="none">
            {text}
        </text>
    </g>"#,
        rx=rx, ry=ry, id=n.id, w=n.w, h=n.h,
        fill=fill, color=n.color, stroke_w=stroke_w,
        tx=n.w/2.0, ty=n.h/2.0,
        text_color=text_color, font_size=font_size, font_weight=font_weight,
        text=escape_xml(&n.text),
        selection_ring=selection_ring,
    )
}
```

### 8.2 エッジ描画（ベジェ曲線）

```rust
fn render_edge(parent: &Node, child: &Node, color: &str, depth: usize) -> String {
    let (px, py) = (parent.x, parent.y);
    let (cx, cy) = (child.x, child.y);
    let dx = cx - px;
    let dy = cy - py;
    let stroke_w = if depth == 1 { 2.5 } else { 1.5 };
    let opacity = if depth == 1 { 0.9 } else { 0.6 };
    format!(
        r#"<path d="M{:.1},{:.1} C{:.1},{:.1} {:.1},{:.1} {:.1},{:.1}"
            stroke="{}" stroke-width="{}" fill="none"
            opacity="{}" stroke-linecap="round"/>"#,
        px, py,
        px + dx * 0.45, py + dy * 0.05,
        cx - dx * 0.45, cy - dy * 0.05,
        cx, cy,
        color, stroke_w, opacity
    )
}
```

### 8.3 描画順序

1. エッジ（全ノード分、`edges-layer`）
2. ノード（全ノード分、`nodes-layer`）

選択中ノードは SVG上で selection ring を追加描画（z-index の代わりに描画順で制御）。

---

## 9. ショートカットキー仕様

### 9.1 グローバルショートカット

| キー | 操作 | 備考 |
|------|------|------|
| `Tab` | 選択ノードに子ノードを追加 | マインドマップツールの慣例 |
| `Enter` | 選択ノードと同階層に兄弟ノードを追加 | ルートノードでは無効 |
| `F2` | 選択ノードのテキスト編集を開始 | |
| `Delete` / `Backspace` | 選択ノードを削除（子孫ごと） | ルートノードでは無効 |
| `Escape` | 選択解除 / 編集キャンセル / メニューを閉じる | 優先度順に適用 |
| `Cmd/Ctrl + Z` | Undo | |
| `Cmd/Ctrl + Shift + Z` | Redo | |
| `Cmd/Ctrl + S` | JSONファイルを保存 | |
| `Cmd/Ctrl + O` | JSONファイルを読込 | |
| `Cmd/Ctrl + K` | コマンドパレットを開く | |
| `Cmd/Ctrl + A` | 全ノードを選択（将来拡張用に予約） | POCでは未実装 |

### 9.2 ビュー操作ショートカット

| キー | 操作 |
|------|------|
| `Cmd/Ctrl + +` / `=` | ズームイン |
| `Cmd/Ctrl + -` | ズームアウト |
| `Cmd/Ctrl + 0` | ビューをリセット（100%・中央） |
| `Space + ドラッグ` | パン（Figmaスタイル） |
| 矢印キー | 選択ノードを隣接ノードに移動（親・子・兄弟） |

### 9.3 矢印キーによるノード間移動ルール

```
←  : 親ノードへ移動
→  : 最初の子ノードへ移動（子がなければ無効）
↑  : 前の兄弟ノードへ移動（なければ無効）
↓  : 次の兄弟ノードへ移動（なければ無効）
```

### 9.4 実装方針（`src/lib/keyboard.ts`）

```typescript
export function setupKeyboardShortcuts(handlers: ShortcutHandlers) {
  window.addEventListener('keydown', (e) => {
    // 編集中（input にフォーカスあり）はショートカットを無効化
    if (isEditingText()) return;

    const mod = e.metaKey || e.ctrlKey;

    if (mod && e.key === 'k') { e.preventDefault(); handlers.openPalette(); return; }
    if (mod && e.key === 'z' && e.shiftKey) { e.preventDefault(); handlers.redo(); return; }
    if (mod && e.key === 'z') { e.preventDefault(); handlers.undo(); return; }
    if (mod && e.key === 's') { e.preventDefault(); handlers.save(); return; }
    if (mod && e.key === 'o') { e.preventDefault(); handlers.load(); return; }
    if (mod && (e.key === '+' || e.key === '=')) { e.preventDefault(); handlers.zoomIn(); return; }
    if (mod && e.key === '-') { e.preventDefault(); handlers.zoomOut(); return; }
    if (mod && e.key === '0') { e.preventDefault(); handlers.resetView(); return; }

    if (e.key === 'Tab')       { e.preventDefault(); handlers.addChild(); return; }
    if (e.key === 'Enter')     { e.preventDefault(); handlers.addSibling(); return; }
    if (e.key === 'F2')        { e.preventDefault(); handlers.editNode(); return; }
    if (e.key === 'Delete' || e.key === 'Backspace') { handlers.deleteNode(); return; }
    if (e.key === 'Escape')    { handlers.escape(); return; }
    if (e.key === 'ArrowLeft') { handlers.navigateParent(); return; }
    if (e.key === 'ArrowRight'){ handlers.navigateChild(); return; }
    if (e.key === 'ArrowUp')   { handlers.navigatePrevSibling(); return; }
    if (e.key === 'ArrowDown') { handlers.navigateNextSibling(); return; }
  });
}
```

---

## 10. コマンドパレット仕様

### 10.1 概要

`Cmd/Ctrl + K` で開くコマンドパレット。キーボードだけで全操作にアクセスできる手段を提供する。VS Code / Linear スタイルのインクリメンタル検索 UI。直近10件のコマンド履歴を localStorage に保存し、次回起動時も維持する。

### 10.2 コマンド一覧

| コマンド名 | アクション | コンテキスト条件 |
|-----------|-----------|----------------|
| `子ノードを追加` | 選択ノードに子ノードを追加 | ノード選択中 |
| `兄弟ノードを追加` | 同階層にノードを追加 | ルート以外を選択中 |
| `ノードを編集` | テキスト編集を開始 | ノード選択中 |
| `ノードを削除` | 選択ノードを子孫ごと削除 | ルート以外を選択中 |
| `自動レイアウト` | 放射状レイアウトを再実行 | 常時 |
| `ファイルを保存` | JSONダウンロード | 常時 |
| `ファイルを読み込む` | JSONアップロード | 常時 |
| `ズームイン` | ビュー拡大 | 常時 |
| `ズームアウト` | ビュー縮小 | 常時 |
| `ビューをリセット` | 100%・中央に戻す | 常時 |

コンテキスト条件を満たさないコマンドはグレーアウトして表示し、選択不可とする。
Undo / Redo はショートカット（`Cmd+Z` / `Cmd+Shift+Z`）専用とし、コマンドパレットには出さない。

### 10.3 UIコンポーネント設計（`CommandPalette.svelte`）

クエリが空のとき（パレットを開いた直後）は「最近使ったコマンド」セクションを最上部に表示する。クエリを入力した瞬間に履歴セクションは消え、通常の絞り込み結果に切り替わる。

```
// クエリ空（開いた直後）
┌─────────────────────────────────────────┐
│ 🔍 コマンドを検索...              Esc  │
├─────────────────────────────────────────┤
│ 最近使ったコマンド                      │
│ ▶ ノードを削除                         │  ← 直近1件目
│   子ノードを追加            Tab        │
│   ファイルを保存            ⌘S         │
│ ────────────────────────────────────    │
│ すべてのコマンド                        │
│   兄弟ノードを追加          Enter      │
│   ...                                   │
└─────────────────────────────────────────┘

// クエリ入力中
┌─────────────────────────────────────────┐
│ 🔍 ノード                         Esc  │
├─────────────────────────────────────────┤
│ ▶ 子ノードを追加            Tab        │
│   兄弟ノードを追加          Enter      │
│   ノードを編集              F2         │
│   ノードを削除                         │
└─────────────────────────────────────────┘
```

**キーボード操作**:
- `↑` / `↓`: 候補を上下移動
- `Enter`: 選択したコマンドを実行し、パレットを閉じる
- `Escape`: パレットを閉じる（履歴は保存しない）
- 文字入力: コマンド名をインクリメンタル検索（日本語対応）

**状態管理**:

```svelte
<script lang="ts">
  let { open = $bindable(false) } = $props();

  let query = $state('');
  let activeIndex = $state(0);
  const HISTORY_KEY = 'mindmap:cmd-history';
  const HISTORY_MAX = 10;

  // 履歴をlocalStorageから復元
  let history = $state<string[]>(
    JSON.parse(localStorage.getItem(HISTORY_KEY) ?? '[]')
  );

  // 履歴に含まれるコマンドを順序付きで返す
  let recentCommands = $derived(
    history
      .map(id => commands.find(c => c.id === id))
      .filter((c): c is Command => !!c && c.available())
  );

  // クエリ空なら全コマンド、入力中なら絞り込み
  let filtered = $derived(
    query === ''
      ? commands.filter(c => c.available())
      : commands
          .filter(c => c.available())
          .filter(c => c.label.includes(query) || c.keywords.some(k => k.includes(query)))
  );

  function execute(cmd: Command) {
    // 履歴に追加（重複排除 + 先頭に追加 + 上限10件）
    history = [cmd.id, ...history.filter(id => id !== cmd.id)].slice(0, HISTORY_MAX);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
    cmd.execute();
    open = false;
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'ArrowDown') { activeIndex = Math.min(activeIndex + 1, filtered.length - 1); }
    if (e.key === 'ArrowUp')   { activeIndex = Math.max(activeIndex - 1, 0); }
    if (e.key === 'Enter')     { execute(filtered[activeIndex]); }
    if (e.key === 'Escape')    { open = false; }
  }

  // パレットを開くたびにリセット
  $effect(() => { if (open) { query = ''; activeIndex = 0; } });
</script>
```

**コマンド定義の型**:

```typescript
interface Command {
  id: string;
  label: string;         // 表示名（日本語）
  keywords: string[];    // 検索用キーワード（英語も含む）
  shortcut?: string;     // 表示用ショートカット文字列（例: "⌘S"）
  available: () => boolean;  // 実行可能かどうか（リアクティブ）
  execute: () => void;
}
```

### 10.4 コマンドパレットの検索仕様

- 日本語・英語の混在検索に対応（`子ノード` でも `child` でも hit）
- `keywords` に英語エイリアスを持たせることで実現
- 部分一致（`includes`）で十分。POCでは fuzzy match は不要

### 10.5 コマンド履歴仕様

| 項目 | 仕様 |
|------|------|
| 保存場所 | `localStorage`（キー: `mindmap:cmd-history`） |
| 保存形式 | コマンドIDの配列をJSON文字列化（例: `["delete-node","add-child"]`） |
| 上限件数 | 10件（超えた場合は古いものから削除） |
| 重複排除 | 同一コマンドを実行した場合、既存エントリを削除して先頭に追加 |
| 永続化タイミング | コマンド実行時（`Enter` 確定時のみ。`Escape` では保存しない） |
| 利用不可コマンドの扱い | 履歴に残っていても `available()` が false なら表示しない |

---

## 11. フェーズ別実装計画

| Phase | 期間 | 内容 | 完了条件 |
|-------|------|------|---------|
| **Phase 0** | 1〜2日 | プロジェクトセットアップ | wasm-pack build が通り、Svelte から WASM 関数を呼び出せる |
| **Phase 1** | 3〜4日 | コアモデル + 描画 | ルートノード＋子ノードが放射状に描画される |
| **Phase 2** | 3〜5日 | ノード操作 + Undo/Redo + ショートカット | 追加・削除・テキスト編集・Undo/Redo・矢印キー移動が動作する |
| **Phase 3** | 2〜3日 | ズーム・パン | マウスホイールズーム、ドラッグパンが動作する |
| **Phase 4** | 1〜2日 | ファイル保存・読込 | JSON ダウンロード/アップロードが動作する |
| **Phase 5** | 2〜3日 | コマンドパレット + 履歴 | `Cmd+K` でパレットが開き、履歴が localStorage に永続化される |
| **バッファ** | 2〜3日 | バグ修正・調整 | — |
| **合計** | **4〜6週間** | | |

---

## 12. 依存ライブラリ一覧

### Rust (`Cargo.toml`)

```toml
[dependencies]
wasm-bindgen = "0.2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
uuid = { version = "1", features = ["v4", "serde", "js"] }

[profile.release]
opt-level = "s"
lto = true
strip = "debuginfo"
```

### Frontend (`package.json`)

```json
{
  "devDependencies": {
    "svelte": "^5.16.0",
    "@sveltejs/vite-plugin-svelte": "^5.0.3",
    "vite": "^6.0.7",
    "vite-plugin-wasm": "^3.4.1",
    "vite-plugin-top-level-await": "^1.4.4",
    "typescript": "^5.7.3"
  }
}
```

**外部ランタイム依存: ゼロ**（node_modules は devDependencies のビルドツールのみ）
