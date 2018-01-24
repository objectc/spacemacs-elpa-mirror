;;; stem-english.el ---- routines for stemming English word -*- lexical-binding: t -*-

;; Author: Tsuchiya Masatoshi <tsuchiya@pine.kuee.kyoto-u.ac.jp>
;; Maintainer: KAWABATA, Taichi <kawabata.taichi_at_gmail.com>
;; Created: 1997
;; Description: routines for stemming English word
;; Package-Requires: ((emacs "24.3"))
;; Package-Version: 20180108.1958
;; Keywords: text
;; Human-Keywords: stemming
;; Version: 2.140226
;; URL: http://github.com/kawabata/stem-english

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; * English word stemmer
;;
;; This library stems an English word, based on the algorithm
;; described in the paper "An algorithm for suffix stripping
;; (M.F.Porter)".
;;
;; Function `stem-english (str)' returns a list of possible stems in
;; order of string length.
;;
;; This is a re-written version of `stem.el' originally written by
;; Tsuchiya Masatoshi, to be compatible with modern Emacs, removing
;; all compiler warnings by explicitly defining lexicographically
;; bounded variables.
;;
;; [original Japanese document]
;;
;; 論文『An algorithm for suffix stripping (M.F.Porter)』に記述されて
;; いるアルゴリズムに基づいて、英単語の語尾を取り除くためのライブラリ。
;; 利用及び再配布の際は、GNU 一般公用許諾書の適当なバージョンにしたがっ
;; て下さい。
;;
;; 一次配布元
;;  http://www-nagao.kuee.kyoto-u.ac.jp/member/tsuchiya/sdic/index.html

;;; Code:

(defvar stem-english--minimum-word-length 4 "Porter のアルゴリズムが適用できる最小語長")
(defvar stem-english--stem)
(defvar stem-english--str)

;;;============================================================
;;;	非公開関数
;;;============================================================

;; 動作速度を向上させるために、関数内部で外部変数をいじっている
;; 関数があり、予期しない副作用が発生する可能性が高い。従って、
;; 非公開関数を直接呼び出すことは避けること。

;;------------------------------------------------------------
;;	stemming-rule の条件節を記述する関数群
;;------------------------------------------------------------

(defsubst stem-english--match (arg) "\
変数 stem-english--str を検査する非公開関数 (語幹の部分を変数 stem-english--stem に代入する)"
  (and
   (string-match arg stem-english--str)
   (setq stem-english--stem (substring stem-english--str 0 (match-beginning 0)))))

(defsubst stem-english--m () "\
変数 stem-english--stem に含まれている VC の数を求める非公開関数"
  (save-match-data
    (let ((pos 0)(m 0))
      (while (string-match "\\(a\\|e\\|i\\|o\\|u\\|[^aeiou]y+\\)[aeiou]*" stem-english--stem pos)
	(setq m (1+ m))
	(setq pos (match-end 0)))
      (if (= pos (length stem-english--stem)) (1- m) m))))

(defsubst stem-english--m> (i) "\
変数 stem-english--stem に含まれている VC の数の条件を記述する非公開関数"
  (< i (stem-english--m)))

(defsubst stem-english--m= (i) "\
変数 stem-english--stem に含まれている VC の数の条件を記述する非公開関数"
  (= i (stem-english--m)))

(defsubst stem-english--*v* () "\
変数 stem-english--stem が母音を含んでいるか検査する関数"
  (save-match-data
    (if (string-match "\\(a\\|e\\|i\\|o\\|u\\|[^aeiou]y\\)" stem-english--stem) t)))

(defsubst stem-english--*o () "\
変数 stem-english--stem が cvc の形で終っているか検査する関数"
  (save-match-data
    (if (string-match "[^aeiou][aeiouy][^aeiouwxy]$" stem-english--stem) t)))



;;------------------------------------------------------------
;;	stemming-rule を記述した関数群
;;------------------------------------------------------------

(defun stem-english--step1a (str) "第1a段階の stemming rule (非公開関数)"
  (let (s stem-english--stem (stem-english--str str))
    (if (setq s (cond
		 ((stem-english--match "sses$") "ss")
		 ((stem-english--match "ies$")  "i")
		 ((stem-english--match "ss$")   "ss")
		 ((stem-english--match "s$")    "")))
	(concat stem-english--stem s)
      stem-english--str)))


(defun stem-english--step1b (str) "第1b段階の stemming rule (非公開関数)"
  (let (s stem-english--stem (stem-english--str str))
    (cond
     ((and (stem-english--match "eed$") (stem-english--m> 0))
      (concat stem-english--stem "ee"))
     ((or (and (not stem-english--stem) (stem-english--match "ed$") (stem-english--*v*))
	  (and (stem-english--match "ing$") (stem-english--*v*)))
      (if (and (stem-english--m= 1) (stem-english--*o))
	  (concat stem-english--stem "e")
	(setq stem-english--str stem-english--stem)
	(if (setq s (cond
		     ((stem-english--match "at$") "ate")
		     ((stem-english--match "bl$") "ble")
		     ((stem-english--match "iz$") "ize")
		     ((stem-english--match "\\([^lsz]\\)\\1$")
		      (substring stem-english--str (match-beginning 1) (match-end 1)))))
	    (concat stem-english--stem s)
	  stem-english--str)))
     (t stem-english--str))))


(defun stem-english--step1c (str) "第1c段階の stemming rule (非公開関数)"
  (let (stem-english--stem (stem-english--str str))
    (if (and (stem-english--match "y$")
	     (stem-english--*v*))
	(concat stem-english--stem "i")
      stem-english--str)))


(defun stem-english--step1 (str) "第1段階の stemming rule (非公開関数)"
  (stem-english--step1c
   (stem-english--step1b
    (stem-english--step1a str))))


(defun stem-english--step2 (str) "第2段階の stemming rule (非公開関数)"
  (let (s stem-english--stem (stem-english--str str))
    (if (and
	 (setq s (cond
		  ((stem-english--match "ational$") "ate")
		  ((stem-english--match "tional$")  "tion")
		  ((stem-english--match "enci$")    "ence")
		  ((stem-english--match "anci$")    "ance")
		  ((stem-english--match "izer$")    "ize")
		  ((stem-english--match "abli$")    "able")
		  ((stem-english--match "alli$")    "al")
		  ((stem-english--match "entli$")   "ent")
		  ((stem-english--match "eli$")     "e")
		  ((stem-english--match "ousli$")   "ous")
		  ((stem-english--match "ization$") "ize")
		  ((stem-english--match "ation$")   "ate")
		  ((stem-english--match "ator$")    "ate")
		  ((stem-english--match "alism$")   "al")
		  ((stem-english--match "iveness$") "ive")
		  ((stem-english--match "fulness$") "ful")
		  ((stem-english--match "ousness$") "ous")
		  ((stem-english--match "aliti$")   "al")
		  ((stem-english--match "iviti$")   "ive")
		  ((stem-english--match "biliti$")  "ble")))
	 (stem-english--m> 0))
	(concat stem-english--stem s)
      stem-english--str)))


(defun stem-english--step3 (str) "第3段階の stemming rule (非公開関数)"
  (let (s stem-english--stem (stem-english--str str))
    (if (and
	 (setq s (cond
		  ((stem-english--match "icate$") "ic")
		  ((stem-english--match "ative$") "")
		  ((stem-english--match "alize$") "al")
		  ((stem-english--match "iciti$") "ic")
		  ((stem-english--match "ical$")  "ic")
		  ((stem-english--match "ful$")   "")
		  ((stem-english--match "ness$")  "")))
	 (stem-english--m> 0))
	(concat stem-english--stem s)
      stem-english--str)))


(defun stem-english--step4 (str) "第4段階の stemming rule (非公開関数)"
  (let (stem-english--stem (stem-english--str str))
    (if (and (or
	      (stem-english--match "al$")
	      (stem-english--match "ance$")
	      (stem-english--match "ence$")
	      (stem-english--match "er$")
	      (stem-english--match "ic$")
	      (stem-english--match "able$")
	      (stem-english--match "ible$")
	      (stem-english--match "ant$")
	      (stem-english--match "ement$")
	      (stem-english--match "ment$")
	      (stem-english--match "ent$")
	      (and (string-match "[st]\\(ion\\)$" stem-english--str)
		   (setq stem-english--stem (substring stem-english--str 0 (match-beginning 1))))
	      (stem-english--match "ou$")
	      (stem-english--match "ism$")
	      (stem-english--match "ate$")
	      (stem-english--match "iti$")
	      (stem-english--match "ous$")
	      (stem-english--match "ive$")
	      (stem-english--match "ize$"))
	     (stem-english--m> 1))
	stem-english--stem stem-english--str)))


(defun stem-english--step5 (str) "第5段階の stemming rule (非公開関数)"
  (let (stem-english--stem (stem-english--str str))
    (if (or
	 (and (stem-english--match "e$")
	      (or (stem-english--m> 1)
		  (and (stem-english--m= 1)
		       (not (stem-english--*o)))))
	 (and (stem-english--match "ll$")
	      (setq stem-english--stem (concat stem-english--stem "l"))
	      (stem-english--m> 1)))
	stem-english--stem stem-english--str)))


(defvar stem-english--irregular-verb-alist
  '(("abode" "abide")
    ("abided" "abide")
    ("alighted" "alight")
    ("arose" "arise")
    ("arisen" "arise")
    ("awoke" "awake")
    ("awaked" "awake")
    ("awoken" "awake")
    ("baby-sat" "baby-sit")
    ("backbit" "backbite")
    ("backbitten" "backbite")
    ("backslid" "backslide")
    ("backslidden" "backslide")
    ("was" "be" "am" "is" "are")
    ("were" "be" "am" "is" "are")
    ("been" "be" "am" "is" "are")
    ("bore" "bear")
    ("bare" "bear")
    ("borne" "bear")
    ("born" "bear")
    ("beat" "beat")
    ("beaten" "beat")
    ("befell" "befall")
    ("befallen" "befall")
    ("begot" "beget")
    ("begat" "beget")
    ("begotten" "beget")
    ("began" "begin")
    ("begun" "begin")
    ("begirt" "begird")
    ("begirded" "begird")
    ("beheld" "behold")
    ("bent" "bend")
    ("bended" "bend")
    ("bereaved" "bereave")
    ("bereft" "bereave")
    ("besought" "beseech")
    ("beseeched" "beseech")
    ("beset" "beset")
    ("bespoke" "bespeak")
    ("bespoken" "bespeak")
    ("bestrewed" "bestrew")
    ("bestrewn" "bestrew")
    ("bestrode" "bestride")
    ("bestrid" "bestride")
    ("bestridden" "bestride")
    ("bet" "bet")
    ("betted" "bet")
    ("betook" "betake")
    ("betaken" "betake")
    ("bethought" "bethink")
    ("bade" "bid")
    ("bid" "bid")
    ("bad" "bid")
    ("bedden" "bid")
    ("bided" "bide")
    ("bode" "bide")
    ("bound" "bind")
    ("bit" "bite")
    ("bitten" "bite")
    ("bled" "bleed")
    ("blended" "blend")
    ("blent" "blend")
    ("blessed" "bless")
    ("blest" "bless")
    ("blew" "blow")
    ("blown" "blow")
    ("blowed" "blow")
    ("bottle-fed" "bottle-feed")
    ("broke" "break")
    ("broken" "break")
    ("breast-fed" "breast-feed")
    ("bred" "breed")
    ("brought" "bring")
    ("broadcast" "broadcast")
    ("broadcasted" "broadcast")
    ("browbeat" "browbeat")
    ("browbeaten" "browbeat")
    ("built" "build")
    ("builded" "build")
    ("burned" "burn")
    ("burnt" "burn")
    ("burst" "burst")
    ("busted" "bust")
    ("bust" "bust")
    ("bought" "buy")
    ("cast" "cast")
    ("chid" "chide")
    ("chided" "chide")
    ("chidden" "chide")
    ("chose" "choose")
    ("chosen" "choose")
    ("clove" "cleave")
    ("cleft" "cleave")
    ("cleaved" "cleave")
    ("cloven" "cleave")
    ("clave" "cleave")
    ("clung" "cling")
    ("clothed" "clothe")
    ("clad" "clothe")
    ("colorcast" "colorcast")
    ("clorcasted" "colorcast")
    ("came" "come")
    ("come" "come")
    ("cost" "cost")
    ("costed" "cost")
    ("countersank" "countersink")
    ("countersunk" "countersink")
    ("crept" "creep")
    ("crossbred" "crossbreed")
    ("crowed" "crow")
    ("crew" "crow")
    ("cursed" "curse")
    ("curst" "curse")
    ("cut" "cut")
    ("dared" "dare")
    ("durst" "dare")
    ("dealt" "deal")
    ("deep-froze" "deep-freeze")
    ("deep-freezed" "deep-freeze")
    ("deep-frozen" "deep-freeze")
    ("dug" "dig")
    ("digged" "dig")
    ("dived" "dive")
    ("dove" "dive")
    ("did" "do")
    ("done" "do")
    ("drew" "draw")
    ("drawn" "draw")
    ("dreamed" "dream")
    ("dreamt" "dream")
    ("drank" "drink")
    ("drunk" "drink")
    ("dripped" "drip")
    ("dript" "drip")
    ("drove" "drive")
    ("drave" "drive")
    ("driven" "drive")
    ("dropped" "drop")
    ("dropt" "drop")
    ("dwelt" "dwell")
    ("dwelled" "dwell")
    ("ate" "eat")
    ("eaten" "eat")
    ("fell" "fall")
    ("fallen" "fall")
    ("fed" "feed")
    ("felt" "feel")
    ("fought" "fight")
    ("found" "find")
    ("fled" "fly" "flee")
    ("flung" "fling")
    ("flew" "fly")
    ("flied" "fly")
    ("flown" "fly")
    ("forbore" "forbear")
    ("forborne" "forbear")
    ("forbade" "forbid")
    ("forbad" "forbid")
    ("forbidden" "forbid")
    ("forecast" "forecast")
    ("forecasted" "forecast")
    ("forewent" "forego")
    ("foregone" "forego")
    ("foreknew" "foreknow")
    ("foreknown" "foreknow")
    ("foreran" "forerun")
    ("forerun" "forerun")
    ("foresaw" "foresee")
    ("foreseen" "foresee")
    ("foreshowed" "foreshow")
    ("foreshown" "foreshow")
    ("foretold" "foretell")
    ("forgot" "forget")
    ("forgotten" "forget")
    ("forgave" "forgive")
    ("forgiven" "forgive")
    ("forwent" "forgo")
    ("forgone" "forgo")
    ("forsook" "forsake")
    ("forsaken" "forsake")
    ("forswore" "forswear")
    ("forsworn" "forswear")
    ("froze" "freeze")
    ("frozen" "freeze")
    ("gainsaid" "gainsay")
    ("gelded" "geld")
    ("gelt" "geld")
    ("got" "get")
    ("gotten" "get")
    ("ghostwrote" "ghostwrite")
    ("ghostwritten" "ghostwrite")
    ("gilded" "gild")
    ("gilt" "gild")
    ("girded" "gird")
    ("girt" "gird")
    ("gave" "give")
    ("given" "give")
    ("gnawed" "gnaw")
    ("gnawn" "gnaw")
    ("went" "go" "wend")
    ("gone" "go")
    ("graved" "grave")
    ("graven" "grave")
    ("ground" "grind")
    ("gripped" "grip")
    ("gript" "grip")
    ("grew" "grow")
    ("grown" "grow")
    ("hamstrung" "hamstring")
    ("hamstringed" "hamstring")
    ("hung" "hang")
    ("hanged" "hang")
    ("had" "have")
    ("heard" "hear")
    ("heaved" "heave")
    ("hove" "heave")
    ("hewed" "hew")
    ("hewn" "hew")
    ("hid" "hide")
    ("hidden" "hide")
    ("hit" "hit")
    ("held" "hold")
    ("hurt" "hurt")
    ("indwelt" "indwell")
    ("inlaid" "inlay")
    ("inlet" "inlet")
    ("inputted" "input")
    ("input" "input")
    ("inset" "inset")
    ("insetted" "inset")
    ("interwove" "interweave")
    ("interweaved" "interweave")
    ("jigsawed" "jigsaw")
    ("jigsawn" "jigsaw")
    ("kept" "keep")
    ("knelt" "kneel")
    ("kneeled" "kneel")
    ("knitted" "knit")
    ("knit" "knit")
    ("knew" "know")
    ("known" "know")
    ("laded" "lade")
    ("laden" "lade")
    ("laid" "lay")
    ("led" "lead")
    ("leaned" "lean")
    ("leant" "lean")
    ("leaped" "leap")
    ("leapt" "leap")
    ("learned" "learn")
    ("learnt" "learn")
    ("left" "leave")
    ("lent" "lend")
    ("let" "let")
    ("lay" "lie")
    ("lain" "lie")
    ("lighted" "light")
    ("lit" "light")
    ("lip-read" "lip-read")
    ("lost" "lose")
    ("made" "make")
    ("meant" "mean")
    ("met" "meet")
    ("melted" "melt")
    ("methougt" "methinks")
    ;; ("-" "methinks")
    ("misbecame" "misbecome")
    ("misbecome" "misbecome")
    ("miscast" "miscast")
    ("miscasted" "miscast")
    ("misdealt" "misdeal")
    ("misdid" "misdo")
    ("misdone" "misdo")
    ("misgave" "misgive")
    ("misgiven" "misgive")
    ("mishit" "mishit")
    ("mislaid" "mislay")
    ("misled" "mislead")
    ("misread" "misread")
    ("misspelt" "misspell")
    ("missplled" "misspell")
    ("misspent" "misspend")
    ("mistook" "mistake")
    ("mistaken" "mistake")
    ("misunderstood" "misunderstand")
    ("mowed" "mow")
    ("mown" "mow")
    ("offset" "offset")
    ("outbid" "outbid")
    ("outbade" "outbid")
    ("outbidden" "outbid")
    ("outdid" "outdo")
    ("outdone" "outdo")
    ("outfought" "outfight")
    ("outgrew" "outgrown")
    ("outgrown" "outgrown")
    ("outlaid" "outlay")
    ("output" "output")
    ("outputted" "output")
    ("ooutputted" "output")
    ("outrode" "outride")
    ("outridden" "outride")
    ("outran" "outrun")
    ("outrun" "outrun")
    ("outsold" "outsell")
    ("outshone" "outshine")
    ("outshot" "outshoot")
    ("outwore" "outwear")
    ("outworn" "outwear")
    ("overbore" "overbear")
    ("overborne" "overbear")
    ("overbid" "overbid")
    ("overblew" "overblow")
    ("overblown" "overblow")
    ("overcame" "overcome")
    ("overcome" "overcome")
    ("overdid" "overdo")
    ("overdone" "overdo")
    ("overdrew" "overdraw")
    ("overdrawn" "overdraw")
    ("overdrank" "overdrink")
    ("overdrunk" "overdrink")
    ("overate" "overeat")
    ("overeaten" "overeat")
    ("overfed" "overfeed")
    ("overflowed" "overflow")
    ("overflown" "overfly" "overflow")
    ("overflew" "overfly")
    ("overgrew" "overgrow")
    ("overgrown" "overgrow")
    ("overhung" "overhang")
    ("overhanged" "overhang")
    ("ovearheard" "overhear")
    ("overlaid" "overlay")
    ("overleaped" "overleap")
    ("overleapt" "overleap")
    ("overlay" "overlie")
    ("overlain" "overlie")
    ("overpaid" "overpay")
    ("overrode" "override")
    ("overridden" "override")
    ("overran" "overrun")
    ("overrun" "overrun")
    ("oversaw" "oversee")
    ("overseen" "oversee")
    ("oversold" "oversell")
    ("overset" "overset")
    ("overshot" "overshoot")
    ("overspent" "overspend")
    ("overspread" "overspread")
    ("overtook" "overtake")
    ("overtaken" "overtake")
    ("overthrew" "overthrow")
    ("overthrown" "overthrow")
    ("overworked" "overwork")
    ("overwrought" "overwork")
    ("partook" "partake")
    ("partaken" "partake")
    ("paid" "pay")
    ("penned" "pen")
    ("pent" "pen")
    ("pinch-hit" "pinch-hit")
    ("pleaded" "plead")
    ("plead" "plead")
    ("pled" "plead")
    ("prepaid" "prepay")
    ("preset" "preset")
    ("proofread" "proofread")
    ("proved" "prove")
    ("proven" "prove")
    ("put" "put")
    ("quick-froze" "quick-freeze")
    ("quick-frozen" "quick-freeze")
    ("quit" "quit")
    ("quitted" "quit")
    ("read" "read")
    ("reaved" "reave")
    ("reft" "reave")
    ("rebound" "rebind")
    ("rebroadcast" "rebroadcast")
    ("rebroadcasted" "rebroadcast")
    ("rebuilt" "rebuild")
    ("recast" "recast")
    ("recasted" "recast")
    ("re-did" "re-do")
    ("re-done" "re-do")
    ("reeved" "reeve")
    ("rove" "reeve")
    ("reheard" "rehear")
    ("relaid" "relay")
    ("remade" "remake")
    ("rent" "rend")
    ("repaid" "repay")
    ("reread" "reread")
    ("reran" "rerun")
    ("rerun" "rerun")
    ("resold" "resell")
    ("reset" "reset")
    ("retook" "retake")
    ("retaken" "retake")
    ("retold" "retell")
    ("rethought" "rethink")
    ("rewound" "rewind")
    ("rewinded" "rewind")
    ("rewrote" "rewrite")
    ("rewritten" "rewrite")
    ("rid" "ride") ;; ("rid" "ride" "rid")
    ("ridded" "rid")
    ("rode" "ride")
    ("ridden" "ride")
    ("rang" "ring")
    ("rung" "ring")
    ("rose" "rise")
    ("risen" "rise")
    ("rived" "rive")
    ("riven" "rive")
    ("roughcast" "roughcast")
    ("roughhewed" "roughhew")
    ("roughhewn" "roughhew")
    ("ran" "run")
    ("run" "run")
    ("sawed" "saw")
    ("sawn" "saw")
    ("said" "say")
    ("saw" "see")
    ("seen" "see")
    ("sought" "seek")
    ("sold" "sell")
    ("sent" "send")
    ("set" "set")
    ("sewed" "sew")
    ("sewn" "sew")
    ("shook" "shake")
    ("shaken" "shake")
    ("shaved" "shave")
    ("shaven" "shave")
    ("sheared" "shear")
    ("shore" "shear")
    ("shorn" "shear")
    ("shed" "shed")
    ("shone" "shine")
    ("shined" "shine")
    ("shit" "shit")
    ("shat" "shit")
    ("shitted" "shit")
    ("shod" "shoe")
    ("shoed" "shoe")
    ("shot" "shoot")
    ("showed" "show")
    ("shown" "show")
    ("shredded" "shred")
    ("shred" "shred")
    ("shrank" "shrink")
    ("shrunk" "shrink")
    ("shrunken" "shrink")
    ("shrived" "shrive")
    ("shrove" "shrive")
    ("shriven" "shrive")
    ("shut" "shut")
    ("sight-read" "sight-read")
    ("simulcast" "simulcast")
    ("simulcasted" "simulcast")
    ("sang" "sing")
    ("sung" "sing")
    ("sank" "sink")
    ("sunk" "sink")
    ("sunken" "sink")
    ("sat" "sit")
    ("sate" "sit")
    ("slew" "slay")
    ("slain" "slay")
    ("slept" "sleep")
    ("slid" "slide")
    ("slidden" "slide")
    ("slunk" "slink")
    ("smelled" "smell")
    ("smelt" "smell")
    ("smote" "smite")
    ("smitten" "smite")
    ("smit" "smite")
    ("sowed" "sow")
    ("sown" "sow")
    ("spoke" "speak")
    ("spoken" "speak")
    ("sped" "speed")
    ("speeded" "speed")
    ("spelled" "spell")
    ("spelt" "spell")
    ("spellbound" "spellbind")
    ("spent" "spend")
    ("spilled" "spill")
    ("spilt" "spill")
    ("spun" "spin")
    ("span" "spin")
    ("spat" "spit")
    ("spit" "spit")
    ("split" "split")
    ("spoiled" "spoil")
    ("spoilt" "spoil")
    ("spoon-fed" "spoon-feed")
    ("spread" "spread")
    ("sprang" "spring")
    ("sprung" "spring")
    ("stood" "stand")
    ("staved" "stave")
    ("stove" "stave")
    ("stayed" "stay")
    ("staid" "stay")
    ("stole" "steal")
    ("stolen" "steal")
    ("stuck" "stick")
    ("stung" "sting")
    ("stank" "stink")
    ("stunk" "stink")
    ("strewed" "strew")
    ("strewn" "strew")
    ("strode" "stride")
    ("stridden" "stride")
    ("struck" "strike")
    ("stricken" "strike")
    ("strung" "string")
    ("strove" "strive")
    ("striven" "strive")
    ("sublet" "sublet")
    ("sunburned" "sunburn")
    ("sunburnt" "sunburn")
    ("swore" "swear")
    ("sware" "swear")
    ("sworn" "swear")
    ("sweat" "sweat")
    ("sweated" "sweat")
    ("swept" "sweep")
    ("swelled" "swell")
    ("swollen" "swell")
    ("swam" "swim")
    ("swum" "swim")
    ("swung" "swing")
    ("took" "take")
    ("taken" "take")
    ("taught" "teach")
    ("tore" "tear")
    ("torn" "tear")
    ("telecast" "telecast")
    ("telecasted" "telecast")
    ("told" "tell")
    ("thought" "think")
    ("thrived" "thrive")
    ("throve" "thrive")
    ("thriven" "thrive")
    ("threw" "thrown")
    ("thrown" "thrown")
    ("thrust" "thrust")
    ("tossed" "toss")
    ("tost" "toss")
    ("trod" "tread")
    ("treaded" "tread")
    ("trode" "tread")
    ("trodden" "tread")
    ("typecast" "typecast")
    ("typewrote" "typewrite")
    ("typewritten" "typewrite")
    ("unbent" "unbend")
    ("unbended" "unbend")
    ("unbound" "unbind")
    ("underbid" "underbid")
    ("underbidden" "underbid")
    ("undercut" "undercut")
    ("underwent" "undergo")
    ("undergone" "undergo")
    ("underlaid" "underlay")
    ("underlay" "underlie")
    ("underlain" "underlie")
    ("underpaid" "underpay")
    ("undersold" "undersell")
    ("undershot" "undershoot")
    ("understood" "understand")
    ("undertook" "undertake")
    ("undertaken" "undertake")
    ("underwrote" "underwrite")
    ("underwritten" "underwrite")
    ("undid" "undo")
    ("undone" "undo")
    ("undrew" "undraw")
    ("undrawn" "undraw")
    ("ungirded" "ungird")
    ("ungirt" "ungird")
    ("unlearnt" "unlearn")
    ("unlearned" "unlearn")
    ("unmade" "unmake")
    ("unsaid" "unsay")
    ("unstuck" "unstick")
    ("unstrung" "unstring")
    ("unwound" "unwind")
    ("upheld" "uphold")
    ("uprose" "uprise")
    ("uprisen" "uprise")
    ("upset" "upset")
    ("upswept" "upsweep")
    ("woke" "wake")
    ("waked" "wake")
    ("woken" "wake")
    ("waylaid" "waylay")
    ("wore" "wear")
    ("worn" "wear")
    ("wove" "weave")
    ("weaved" "weave")
    ("woven" "weave")
    ("wed" "wed")
    ("wedded" "wed")
    ("wept" "weep")
    ("wended" "wend")
    ("wetted" "wet")
    ("wet" "wet")
    ("won" "win")
    ("wound" "wind")
    ("winded" "wind")
    ("wiredrew" "wiredraw")
    ("wiredrawn" "wiredraw")
    ("wist" "wit")
    ("withdrew" "withdraw")
    ("withdrawn" "withdraw")
    ("withheld" "withhold")
    ("withstood" "withstand")
    ("worked" "work")
    ("wrought" "work")
    ("wrapped" "wrap")
    ("wrapt" "wrap")
    ("wrung" "wring")
    ("wrote" "write")
    ("writ" "write")
    ("written" "write"))
  "不規則動詞と原形の連想配列")


(defun stem-english--extra (str) "\
動詞/形容詞の活用形と名詞の複数形の活用語尾を取り除く非公開関数
与えられた語の原形として可能性のある語のリストを返す"
  (or (assoc str stem-english--irregular-verb-alist)
      (if (string= str "as") (list "as"))
      (let (c l stem-english--stem (stem-english--str str))
	(setq l (cond
		 ;; 比較級/最上級
		 ((stem-english--match "\\([^aeiou]\\)\\1e\\(r\\|st\\)$")
		  (list (substring stem-english--str (match-beginning 1) (match-end 1))
			(substring stem-english--str (match-beginning 0) (match-beginning 2))))
		 ((stem-english--match "\\([^aeiou]\\)ie\\(r\\|st\\)$")
		  (setq c (substring str (match-beginning 1) (match-end 1)))
		  (list c (concat c "y") (concat c "ie")))
		 ((stem-english--match "e\\(r\\|st\\)$") '("" "e"))
		 ;; 3単現/複数形
		 ((stem-english--match "ches$") '("ch" "che"))
		 ((stem-english--match "shes$") '("sh" "che"))
		 ((stem-english--match "ses$") '("s" "se"))
		 ((stem-english--match "xes$") '("x" "xe"))
		 ((stem-english--match "zes$") '("z" "ze"))
		 ((stem-english--match "ves$") '("f" "fe"))
		 ((stem-english--match "\\([^aeiou]\\)oes$")
		  (setq c (substring stem-english--str -4 -3))
		  (list c (concat c "o") (concat c "oe")))
		 ((stem-english--match "\\([^aeiou]\\)ies$")
		  (setq c (substring stem-english--str -4 -3))
		  (list c (concat c "y") (concat c "ie")))
		 ((stem-english--match "es$") '("" "e"))
		 ((stem-english--match "s$") '(""))
		 ;; 過去形/過去分詞
		 ((stem-english--match "\\([^aeiou]\\)ied$")
		  (setq c (substring stem-english--str -4 -3))
		  (list c (concat c "y") (concat c "ie")))
		 ((stem-english--match "\\([^aeiou]\\)\\1ed$")
		  (list (substring stem-english--str -4 -3)
			(substring stem-english--str -4 -1)))
		 ((stem-english--match "cked$") '("c" "cke"))
		 ((stem-english--match "ed$") '("" "e"))
		 ;; 現在分詞
		 ((stem-english--match "\\([^aeiou]\\)\\1ing$")
		  (list (substring stem-english--str -5 -4)))
		 ((stem-english--match "ing$") '("" "e"))
		 ))
	(append (mapcar (lambda (s) (concat stem-english--stem s)) l)
		(list stem-english--str))
	)))



;;;============================================================
;;;	公開関数
;;;============================================================

(defun stem-english--stripping-suffix (str) "\
活用語尾を取り除く関数
与えられた語の元の語として可能性のある語の辞書順のリストを返す"
  (save-match-data
    (delq nil (let ((w ""))
		(mapcar
		 (lambda (x) (if (string= x w) nil (setq w x)))
		 (sort (append
			;; 大文字を小文字に変換
			(list (prog1 str (setq str (downcase str))))
			;; 独自のヒューリスティックスを適用
			(stem-english--extra str)
			(if (> (length str) stem-english--minimum-word-length)
			    ;; 単語長が条件を満たせば、Porter のアルゴリズムを適用
			    (mapcar
			     (lambda (func)
			       (setq str (funcall func str)))
			     '(stem-english--step1 stem-english--step2 stem-english--step3 stem-english--step4 stem-english--step5))))
		       'string<))))))

;;;###autoload
(defun stem-english (str)
;;  "活用語尾を取り除く関数
;; 与えられた語の元の語として可能性のある語の文字列長の昇順のリストを返す"
  (sort (stem-english--stripping-suffix str)
	(lambda (a b) (< (length a) (length b)))))

(defun stem-english-smart (word)
    "My smart apply of `stem-english'."
    (let ((stem-word (stem-english word)))
      (if (= 1 (length stem-word))
          word
        (nth 1 stem-word))))

;; この stem-english の動作は、
;;
;;     Id: stem.el,v 1.4 1998/11/30 09:27:27 tsuchiya Exp tsuchiya
;;
;; 以前のバージョンの stem.el で定義されていた stem:stripping-suffix
;; の動作と互換である。現在の stem:stripping-suffix は辞書順のリストを
;; 返すため、異なる動作とするようになっているので注意すること。

;;; Porter のアルゴリズムを適用する関数
(defun stem-english--stripping-inflection (word) "\
Porter のアルゴリズムに基づいて派生語を処理する関数"
  (save-match-data
    (stem-english--step5
     (stem-english--step4
      (stem-english--step3
       (stem-english--step2
	(stem-english--step1 word)))))))

(provide 'stem-english)

;; Local Variables:
;; time-stamp-pattern: "10/Version:\\\\?[ \t]+2.%02y%02m%02d\\\\?\n"
;; End:

;;; stem-english.el ends here
