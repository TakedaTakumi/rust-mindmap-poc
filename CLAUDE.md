# CLAUDE.md

このファイルは、リポジトリで作業する Claude Code (claude.ai/code) へのガイダンスを提供します。

## プロジェクト概要

ブラウザベースのマインドマップエディタ（POC）。スタック: Rust を WASM にコンパイルしたコアロジック + Svelte 5 TypeScript フロントエンド。仕様書は [.spec/mindmap-spec.md](.spec/mindmap-spec.md) を参照。

**現状:** インフラのみ構築済み。`rust-core/` および `frontend/` ディレクトリは未作成。

## 開発環境

VS Code Dev Containers を使用。VS Code で開き → `Ctrl+Shift+P` → "Dev Containers: Reopen in Container"。ツールチェーン（Rust、wasm-pack、Node v22、pnpm）はコンテナ内にプリインストール済み。

デブコンテナのポート:
- `5173` — Vite 開発サーバー
- `5174` — Vite HMR

## コマンド

**デブコンテナ内:**
```bash
# ツールチェーン確認
rustc --version && wasm-pack --version && node --version && pnpm --version

# WASM ビルド
wasm-pack build rust-core/

# フロントエンド
cd frontend && pnpm install && pnpm dev

# フルビルド（build.sh 作成後）
./build.sh
```

**ホストから:**
```bash
docker compose up --build   # 本番ビルド。http://localhost:8080 で配信
```

## アーキテクチャ

### 責務の分離

| 関心事 | WASM (Rust) | Svelte (TypeScript) |
|--------|-------------|---------------------|
| ノードデータ・CRUD | ✅ | ❌ |
| 放射状レイアウトアルゴリズム | ✅ | ❌ |
| SVG 生成 | ✅ | ❌ |
| JSON シリアライズ | ✅ | ❌ |
| DOM イベント・ドラッグ・ズーム/パン | ❌ | ✅ |
| ビュー状態（選択・インライン編集） | ❌ | ✅ |
| 座標変換 | ❌ | ✅ |
| ファイル I/O（JSON 保存・読み込み） | ❌ | ✅ |

### ディレクトリ構成（予定）

```
rust-core/src/
  lib.rs          # wasm-bindgen エントリポイント
  model.rs        # Node, MindMap 構造体
  layout.rs       # 放射状レイアウトアルゴリズム
  renderer.rs     # SVG 文字列生成
  serializer.rs   # JSON シリアライズ

frontend/src/
  lib/
    wasm.ts       # WASM ラッパー & TypeScript 型定義
    interaction.ts # 座標変換・ドラッグ・ズーム
    fileio.ts     # ファイル保存・読み込み
  components/
    Canvas.svelte, Toolbar.svelte, StatusBar.svelte, ContextMenu.svelte
```

### コアデータモデル

```rust
pub struct Node {
    pub id: String,
    pub text: String,
    pub x: f64, pub y: f64,        // 中心座標
    pub width: f64, pub height: f64,
    pub color: String,              // ブランチカラー（継承）
    pub parent_id: Option<String>,
    pub children_ids: Vec<String>,
}

pub struct MindMap {
    pub version: u32,
    pub name: String,
    pub root_id: String,
    pub nodes: HashMap<String, Node>,
}
```

### 実装上の重要ルール

- WASM を変更した後は必ず `invalidate()` を呼び出して再レンダリングをトリガーする
- ノード選択は `data-node-id` 属性 + `closest()` DOM クエリで行う
- JS↔WASM のデータ交換は JSON 文字列経由（構造体の直接渡しではない）
- Docker のポートフォワーディングのため、Vite config は必ず `host: '0.0.0.0'` を設定する

### レイアウトアルゴリズム

- ルートノードを中心（600, 400）に配置
- 子ノードは半径 = 200 × 深さ で配置
- 角度はリーフ数に比例して分配。隣接ノード間の最小間隔は 0.3 rad
- 幅の推定に CJK 全角文字のサポートを含む

### キーボードショートカット（実装予定）

`Tab` 子ノード追加、`Enter` 兄弟ノード追加、`F2` テキスト編集、`Delete` ノード削除、`Ctrl+S` JSON 保存、`Ctrl+O` JSON 読み込み、`Escape` 選択解除

## Docker ビルドステージ

| ステージ | ベース | 用途 |
|---------|--------|------|
| `base` | debian:bookworm-slim | ツールチェーン（Rust + Node + pnpm + vscode ユーザー） |
| `dev` | base | デブコンテナ（/workspace をバインドマウント） |
| `builder` | base | CI: ソースをコピーして build.sh を実行 |
| `production` | nginx:alpine | frontend/dist を配信 |
