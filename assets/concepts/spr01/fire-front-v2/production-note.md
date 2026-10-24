# 正面発射v2：種反動・水の長い膨張

- 対象: 共有HEAD151a53f＋既存差分、2026-10-20。新規fire-front-v2と専用self証拠のみ。v1/runtime/game/docs/ticketは未変更、親の保全baselineは触らない。Godot/import・OS入力・前面化・再委任・commitなし。
- 種: 4コマ[33,50,50,67]ms、200ms・release33msを維持。F1だけ胴/顔/手を+1px、最外側の手先1画素（x1/x22）は元y27→29の計+2px、間のy28は消して本体側へ接続。足32/33固定。葉はv1の同じ相対画素形のまま胴へ追従+1px、socket(12,13)→(12,14)。他3コマのキャラ/葉はv1維持。
- 水: 6コマ[40,60,50,60,80,110]ms、開始[0,40,100,150,210,290]、400msでidle。release150ms。最初の形成FXは2×2→4×4→6×6、非透明画素4→12→32。飛翔玉も6×6の丸い画素形。150ms以降の形成層は空、別projectileへ分離。
- 水の胴/顔dy=[0,0,-1,+1,+1,0]。溜めF2は顔/上胴/葉を1px上へ伸ばし、下胴y31を残して足32/33へ接続。押出しF3は+1px沈み、手先も追加1px。足を浮かせずジャンプにしない。葉はv1の開き・押出し・遅れ復帰を使い、追加の大玉保持poseを描いた。水の数値/追加形は親の比較初期値。
- 全10キャラ24×36・anchor(12,34)、元8色/二値α/線なし/両眼各1×2px/二枚葉の非対称。キャラ・形成FX・飛翔弾を別grid/palette/透過PNGへ分離。種sheet96×36、水sheet144×36。idleは採用down.pngとbyte一致。
- v1のauthor/export/build_preview/HTMLをv2へ再利用し、出力パス、コマ数、時間/ラベル/検査を更新。編集元・原寸PNG・各layer sheet・manifest・contact-sheet・GIF・自立HTMLを保存。
- GIFは20ms×100コマ＝2000ms、上段6倍実速/下段2倍で1/4速。下段も400ms復帰とidleまで表示。GIFイベントは種40ms/水160msに近似するが、manifest/HTMLは正確な33/150ms。HTMLの停止/実速/スロー/FX切替/境界送りは既存UIを継承。整数矩形・nearest、GIF量子化なし。
- 自己確認1回PASS: 数/寸法/二値α/palette/目・口・足/枠内、種葉の相対画素形保持、F1顔+1/手先+2、溜め下胴接続、水の三段成長と150ms分離、HTML埋込データ/時間境界とJS構文、GIF全100コマの復号RGB/20ms。全コマ一覧を1回目視。比較飛翔で目は隠れず、口への連続重なりは種11ms/水17msまで。
- 証拠: evidence/spr01/fire-front-v2/self/ のself-check.json、html-check.json、preview-script-check.js、target-hashes.json。NOT_RUN: HTML/GIF連続再生の目視・実速印象、物理更新精度、ゲーム統合/範囲/消費/連射/弾道調整、美術採用。

| 凍結対象 | SHA256 |
|---|---|
| seed-character-sheet.png | 6e8956e1d33b326f7d66301c04d3f245792fa4db83cb4f6a38bcf5db3fd82b39 |
| water-character-sheet.png | 96182e92c5552e1cbba838315efc8d684b63c1fa630f9ff032cba65a1c3b9964 |
| manifest.json | 66659a8d8834b41fd7d58d056e6a651121a87c3c2197dc0d7dfea34633d1058a |
| comparison.gif | ccac6deb8e120bdd86658ec59969af9b849173a5733f66bb6bb9b932d607ad3b |
| comparison.html | 7d4785fc5a31390c9a767cf3ec2a77f98d687a9a0bb0580d2412a910644722d8 |

独立確認とユーザー評価へ渡し、凍結・停止する。
