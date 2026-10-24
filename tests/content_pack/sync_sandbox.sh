#!/bin/bash
# リポジトリの content_pack 関連を隔離プロジェクトへ同期する。Godotは隔離側でだけ実行する。
#   sync_sandbox.sh          同期(project.godot も再生成)
#   sync_sandbox.sh pull     隔離側の evidence/content_pack(self/ independent/ を除く)と、生成した assets/content_pack・data/content_pack/sprites.json をリポジトリへ回収
#   (生成物を回収する前に再同期すると、リポジトリ側にない生成物は --delete で消えるので注意)
set -e
REPO=/mnt/c/godot/greenvader
SB=/mnt/c/godot/greenvader_content_sandbox
if [ "$1" = "pull" ]; then
  mkdir -p "$REPO/evidence/content_pack"
  # 隔離側のGodotが作る *.import と *.uid はリポジトリへ持ち込まない
  # 第1弾の証拠 self/ independent/ は凍結済みのため回収しない(隔離側で回帰を再実行しても上書きしない)
  [ -d "$SB/evidence/content_pack" ] && rsync -a --exclude='/self/' --exclude='/independent/' --exclude='*.import' --exclude='*.uid' "$SB/evidence/content_pack/" "$REPO/evidence/content_pack/"
  echo "pulled evidence"
  # 隔離側で生成した仮スプライトとそのメタ情報も回収する
  if [ -d "$SB/assets/content_pack" ]; then
    mkdir -p "$REPO/assets/content_pack"
    rsync -a --exclude='*.import' --exclude='*.uid' "$SB/assets/content_pack/" "$REPO/assets/content_pack/"
    echo "pulled assets"
  fi
  [ -f "$SB/data/content_pack/sprites.json" ] && cp -a "$SB/data/content_pack/sprites.json" "$REPO/data/content_pack/sprites.json" && echo "pulled sprites.json"
  exit 0
fi
mkdir -p "$SB"
for p in scripts/content_pack data/content_pack assets/content_pack scenes/content_pack tests/content_pack; do
  if [ -d "$REPO/$p" ]; then
    mkdir -p "$SB/$p"
    rsync -a --delete --exclude='*.uid' --exclude='*.import' "$REPO/$p/" "$SB/$p/"
  fi
done
{
  echo '; 隔離実行用(生成物。リポジトリの project.godot の表示・描画設定を写す)'
  echo 'config_version=5'
  echo
  echo '[application]'
  echo 'config/name="greenvader content sandbox"'
  echo 'run/main_scene="res://scenes/content_pack/content_lab.tscn"'
  echo 'config/features=PackedStringArray("4.7", "Forward Plus")'
  echo
  awk '/^\[display\]/{p=1} /^\[physics\]/{p=0} p' "$REPO/project.godot"
} > "$SB/project.godot"
echo "synced to $SB"
