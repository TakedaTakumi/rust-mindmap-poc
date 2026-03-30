# MindMap POC

Rust (WASM) + Svelte 5 で構築するブラウザ向けマインドマップツールの POC。

## 技術スタック

- **Rust → WebAssembly**: データモデル・レイアウト計算・SVG生成
- **Svelte 5 + TypeScript**: UI・インタラクション・ファイル I/O
- **Vite**: フロントエンドビルド
- **pnpm**: Node.js パッケージマネージャー

## 開発環境のセットアップ

### 前提条件

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [VS Code](https://code.visualstudio.com/) + [Dev Containers 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

### devcontainer で起動

1. VS Code でこのリポジトリを開く
2. `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**
3. 初回ビルドは数分かかります（Rust ツールチェーン・wasm-pack・Node.js のインストール）

コンテナ内には以下がインストールされています:

- Rust (stable) + `wasm32-unknown-unknown` ターゲット
- wasm-pack
- Node.js 22 LTS + pnpm

## 本番ビルド・デプロイ

```bash
docker compose up --build
```

nginx が `http://localhost:8080` で静的ファイルを配信します。

## プロジェクト構成 (予定)

```
/
├── rust-core/          # Rust WASM ライブラリ
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── model.rs
│       ├── layout.rs
│       ├── renderer.rs
│       └── serializer.rs
├── frontend/           # Svelte 5 アプリ
│   ├── package.json
│   ├── vite.config.ts
│   └── src/
├── build.sh            # wasm-pack ビルドスクリプト
├── Dockerfile
└── docker-compose.yml
```

## 仕様

[.spec/mindmap-spec.md](.spec/mindmap-spec.md) を参照。
