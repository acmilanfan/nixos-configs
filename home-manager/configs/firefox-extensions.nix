{ buildFirefoxXpiAddon, fetchurl, stdenv }: {

  "german-dictionary" = buildFirefoxXpiAddon rec {
    pname = "german-dictionary";
    version = "2.0.6.1webext";
    addonId = "de-DE@dictionaries.addons.mozilla.org";
    url = "https://addons.mozilla.org/firefox/downloads/file/1163876/german_dictionary-${version}.xpi?src=";
    sha256 = "1q79kh0danwmhyyliba74vc5hqknlcf1r59qmih683yzkxgfzvx7";
    meta = with stdenv.lib; {
      description = "German Dictionary (new Orthography) for spellchecking in Mozilla products";
      license = licenses.lgpl21;
      platforms = platforms.all;
    };
  };
  "russian-dictionary" = buildFirefoxXpiAddon rec {
    pname = "russian-dictionary";
    version = "0.4.5.1webext";
    addonId = "ru@dictionaries.addons.mozilla.org";
    url = "https://addons.mozilla.org/firefox/downloads/file/1163927/russian_spellchecking_dictionary-${version}.xpi?src=";
    sha256 = "06hg3iqymsrandbg8v4vyyckabm4vj97gf9q2qhjram8hsybz0c6";
    meta = with stdenv.lib; {
      homepage = "https://mozilla-russia.org/";
      description = "Russian spellchecking dictionary";
      license = licenses.bsd2;
      platforms = platforms.all;
    };
  };
  "leechblock-ng" = buildFirefoxXpiAddon rec {
    pname = "leechblock-ng";
    version = "1.0.5";
    addonId = "leechblockng@proginosko.com";
    url = "https://addons.mozilla.org/firefox/downloads/file/3542788/leechblock_ng-${version}-an+fx.xpi?src=";
    sha256 = "14ahx7x4y2ry0182cb2bfd620glfa9yqsz50k0qrz9cb7yyb9hkp";
    meta = with stdenv.lib; {
      homepage = "https://www.proginosko.com/leechblock/";
      description = "LeechBlock NG is a simple productivity tool designed to block those time-wasting sites that can suck the life out of your working day. All you need to do is specify which sites to block and when to block them.";
      license = licenses.mpl20;
      platforms = platforms.all;
    };
  };
  "neat-url" = buildFirefoxXpiAddon rec {
    pname = "neat-url";
    version = "5.0.0";
    addonId = "neaturl@hugsmile.eu";
    url = "https://addons.mozilla.org/firefox/downloads/file/970953/neat_url-${version}-an+fx.xpi?src=";
    sha256 = "0q8sm3mxizzj457graa5f4lyn5pqyqn385ibhv0s9y2b8brdq63r";
    meta = with stdenv.lib; {
      homepage = "https://github.com/Smile4ever/Neat-URL";
      description = "Remove garbage from URLs";
      license = licenses.gpl2;
      platforms = platforms.all;
    };
  };
  "simple-translate" = buildFirefoxXpiAddon rec {
    pname = "simple-translate";
    version = "2.3.0";
    addonId = "simple-translate@sienori";
    url = "https://addons.mozilla.org/firefox/downloads/file/3427958/simple_translate-${version}-fx.xpi?src=";
    sha256 = "0yzphahlks4ciz1r6afvrhifsw3yr4id5pm4j78ssyvdxpcl1pr6";
    meta = with stdenv.lib; {
      homepage = "https://github.com/sienori/simple-translate";
      description = "Quickly translate selected text on web page. In toolbar popup, you can translate input text.";
      license = licenses.mpl20;
      platforms = platforms.all;
    };
  };
  "grammarly" = buildFirefoxXpiAddon rec {
    pname = "grammarly";
    version = "8.863.0";
    addonId = "87677a2c52b84ad3a151a4a72f5bd3c4@jetpack";
    url = "https://addons.mozilla.org/firefox/downloads/file/3471944/grammarly_for_firefox-${version}-an+fx.xpi?src=";
    sha256 = "1zshkgaz8hsdvnrp1dvn4mj2zj6drpfpiy2kiyv0j4zhzmqbb6m7";
    meta = with stdenv.lib; {
      homepage = "https://www.grammarly.com/";
      description = "Grammarly will help you communicate more effectively. As you type, Grammarly flags mistakes and helps you make sure your messages, documents, and social media posts are clear, mistake-free, and impactful.";
      license = licenses.unfree;
      platforms = platforms.all;
    };
  };
  "ticktick" = buildFirefoxXpiAddon rec {
    pname = "ticktick";
    version = "1.1.3.6";
    addonId = "{52198036-5173-4877-a8e8-62474781798d}";
    url = "https://addons.mozilla.org/firefox/downloads/file/3511196/ticktick_todo_task_list_reminder-${version}-fx.xpi?src=";
    sha256 = "10abqz3p2z00g49ya3xvpn3ii0klsvsby16r1hm3hzmafd6klkqi";
    meta = with stdenv.lib; {
      homepage = "https://ticktick.com/";
      description = "Your wonderful to-do & task list to make all things done and get life well organized.
                     The Addon can help you to save the text on web page as a TickTick task easily.
                     And show your task count on Toolbar badge.";
      license = licenses.mpl20;
      platforms = platforms.all;
    };
  };
  "matte-black-violet-theme" = buildFirefoxXpiAddon rec {
    pname = "matte-black-violet-theme";
    version = "2019.12.27";
    addonId = "{ad213ecb-ae95-4ac8-ac7a-5925ba36ea1d}";
    url = "https://addons.mozilla.org/firefox/downloads/file/3475708/matte_black_violet-${version}-an+fx.xpi?src=dp-btn-primary";
    sha256 = "1s4il8zy3wb8r4ns80xz3cgkccrqf0qb1h17mw7mjzczrv04ds6k";
    meta = with stdenv.lib; {
      homepage = "https://elijahlopez.herokuapp.com/software/#matte-black-theme";
      description = "A modern dark / Matte Black theme with a violet accent color";
      license = licenses.cc-by-nc-sa-30;
      platforms = platforms.all;
    };
  };

}
