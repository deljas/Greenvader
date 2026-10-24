# POC3-VISIBILITY 自己報告

- 対象版: 実行前後ともHEAD `aecdf159ea46ba058d10ff18f785f4fa15fafde3`。並行SAVE-BASEの4ファイル/文書差分は保持し未編集。対象world_viewのbefore SHA256 `d1caa2c77285160faee5e9a4b194c71afec42313d12ac973b1d9f704ff766778`、after `ABB814238E321A62ABC303634B2FF15F556143D75A3CE482414C7549CBACD17A`。最終自己試験hashは `execution_context.json`。
- 実差分: `scripts/poc2/view/world_view.gd` の_entitiesでsession.visibleによる除外を化石だけに限定し、理由コメント1行追加。生存中の敵/固定巣/親玉は通常のカメラ/深度処理へ任せる。戦闘、マップ、化石収集、保存、素材、描画設定は変更なし。
- 試験: `tests/poc3/visibility/self_visibility.gd`。通常Sessionを基にした表示専用fixtureで建物を除き、カメラ中心から64logic（旧視界内）/100logic（旧視界外）にenemy/固定巣/motherを各1体。実際のsession.revealとworld_viewで計測。旧視界半径72、接近による巣起動90に対してfarは外側。各対象のscreen座標、in_camera、old_visible、renderedをbefore/after.jsonへ記録。
- 初期再現: before 8 PASS / 0 FAIL（再現確認をPASSと記録）。GPU画像でnear3体は存在しfar3体は消失、各farはold_visible=falseかつin_camera=true。`before.png` を目視。before.logに空Blocks mesh作成エラー3件あり、これは建物を全除去したfixtureに起因。afterではカメラ外のセル(0,0)だけ壁にして空配列を回避、対象位置/カメラ/視認/描画条件は同一。ゲーム実装でこの非関連処理は修正せず、初期ログ/結果/画像をそのまま保持しbeforeは再走しない。
- 修正後: after 11 PASS / 0 FAIL、exit 0、ログにエラーなし。6対象すべて表示、描画で保存状態不変、化石距離フィルタ維持、発見済み化石は非表示、死亡/配列除去で表示ノード削除。combatを0.25秒1刻みだけ進め、画面内far固定巣/motherは休眠を維持。`after.png` を目視しfar3体の出現を確認。
- import/安全: Godot 4.7.2 import 1回 exit 0。CONTENT-01共有資源なし/Godot0件を各実行直前に確認。APPDATA/LOCALAPPDATAは自己 `profile/` へ隔離、保存APIは使用せず。既存override.cfgがないことを確認し、親の予約範囲内で一時overrideを作成、try/finallyで除去。内容は `startup_override.cfg` に保持。
- 起動前設定: `[display] window/size/no_focus=true`、`window/size/mode=1`。before/afterともProjectSettings値、runtime root.unfocusable=true / root.mode=1、終了時にも同値を確認。起動から最小化を維持し、復元/前面化/OS入力/カーソル操作なし。公式参照: [ProjectSettings no_focus/mode/override.cfg](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-display-window-size-no-focus)。
- 描画: Forward+/Vulkan RTX 5070 Ti。最小化を解除せずSubViewport UPDATE_ALWAYSとRenderingServer.force_draw(false)で640×360画像取得。nearest/整数倍率/MSAAなし/画面AAなしを確認。輪郭線の追加や既存の画素条件の変更なし。nativeウィンドウの可視外観確認とは区別する。
- 終了: override.cfg除去、Godot0件を確認。対象実装と自己試験の編集/実行停止。
- NOT_RUN: 物理入力、建物遮蔽回帰（fixtureは建物なし）、マップ情報、広いゲーム回帰、全照明/全ウィンドウサイズ。通常表示の限定修正でありPoC3全体の受入ではない。
- 文書担当へ: 通常画面の敵/固定巣/動く親玉は距離視認で隠さない。化石・マップ情報・巣の接近/緑化による活動条件は変更なし。初期再現とafterの主要結果、最小化撮影の限界、上記NOT_RUNを記録へ渡す。
