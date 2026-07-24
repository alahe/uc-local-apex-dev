---
title: Sisseelamise kontrollnimekiri
description: Sammsammuline sisseelamisjuhend uutele tiimiliikmetele — eeltingimused, õigused, seadistus, igapäevane kasutus, jälgimine ja elutsükli käsud nii DB+ORDS kui ADB Free stackile.
---

import { Tabs, TabItem } from "@astrojs/starlight/components";

See leht on uue tiimiliikme "alusta siit" kontrollnimekiri, et seadistada **uc-local-apex-dev** esimest
korda. Lehe eesmärk on suunata detailsete juhendite juurde, mitte neid dubleerida — kasuta seda lehte, et
teada, *mida* teha ja *mis järjekorras*, ning järgi linke, et teada saada, *kuidas*.

Kõik siin toodud kehtib mõlema stacki puhul, mida projekt toetab:

- **DB + ORDS** (vaikimisi, kaks konteinerit, täielik kontroll) — vaata [Alustamine](/products/uc-local-apex-dev/docs/getting-started/)
- **ADB Free** (üks kõik-ühes konteiner, lihtsam seadistus, mõned piirangud) — vaata [ADB Free](/products/uc-local-apex-dev/docs/getting-started/adb-free/)

APEX-rakenduste lokaalseks arendamiseks piisab ühest neist. Kui ei ole kindel, kumba tiim kasutab, küsi tiimijuhilt —
vaata [Arhitektuuri ülevaadet](/products/uc-local-apex-dev/docs/reference/architecture/) kõrvutavat võrdlust.

## 1. Riistvara ja VM-i eeltingimused

| | DB + ORDS | ADB Free |
|---|---|---|
| Minimaalne RAM | 4 GB | 8 GB |
| Minimaalne CPU-de arv | 3 | 4 |
| Ketta ruum | ~35 GB | ~35 GB+ |
| Lisanõuded | — | `/dev/fuse` seade |

:::caution[Ressursinõuded]
Vaikimisi Podman/Docker VM macOS-il ja Windowsil ei vasta tihti nendele miinimumidele. Aluspiirid on kõige
levinum põhjus, miks "andmebaas ei lõpeta kunagi käivitumist". Vaata [Alustamise ressursinõuete märkust](/products/uc-local-apex-dev/docs/getting-started/#prerequisites)
ja macOS-il [Podmani seadistusjuhendit](/products/uc-local-apex-dev/docs/other/podman-on-mac/).
:::

### Platvormi märkused

- **macOS** — [loe Podmani seadistusjuhendit](/products/uc-local-apex-dev/docs/other/podman-on-mac/) enne esimest käivitamist.
- **Windows** — installi kõigepealt [Podman Desktop](https://podman-desktop.io/) (**kohustuslik** — see paketeerib Podman CLI ja seadistab WSL2 masina automaatselt, kiireim viis töötava keskkonna saamiseks). Seejärel installi Ubuntu WSL2-le ja SQLcl *WSL2 distro sees* (lingid [Alustamine → Windows kasutajatele](/products/uc-local-apex-dev/docs/getting-started/#windows-users)).
- **Linux** — VM-kihti ei ole; konteinerid töötavad otse.

## 2. Vajalik tarkvara

Mõned asjad kehtivad iga platvormi puhul:

- **Git** — pane tähele, et VS Code sisseehitatud Source Control vaade on `git` käsurea tööriista peale
  ehitatud kasutajaliides, mitte selle asendus. `git` käivitatav fail peab olema tegelikult installitud ja
  `PATH`-il, isegi kui sa ei kirjuta kunagi `git` käsku käsitsi (Windows: [Git for Windows](https://git-scm.com/download/win),
  või `sudo apt install git` Ubuntu-on-WSL2 sees, kuna projekti skriptid jooksevad sealt).
- **Bash-ühilduv shell** (macOS/Linuxil sisseehitatud, Windowsil WSL2)
- Soovitatav: **VS Code** koos AI koodiabilisega (nt GitHub Copilot) — vaata [Igapäevane kasutus](#5-igapäevane-kasutus) allpool, miks
- Valikuline: brauseris usaldusväärne HTTPS-sertifikaat. `create-self-signed-certificates` kasutab esmalt
  `openssl` (olemas peaaegu kõikjal vaikimisi) ja langeb tagasi [mkcert](https://github.com/FiloSottile/mkcert)-ile
  vaid siis, kui `openssl` puudub — enamik inimesi ei vajagi mkcerti kunagi. Vaata
  [SSL seadistust](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration).

Konteinerimootor, Compose ja SQLcl erinevad platvormide vahel piisavalt, et neid eraldi käsitleda:

<Tabs>
<TabItem label="Windows">

- **Konteinerimootor + Compose**: installi [Podman Desktop](https://podman-desktop.io/). Üks installimine
  katab *mõlemad* — see paketeerib Podman CLI ja `podman compose` ning seadistab WSL2 masina sinu eest.
  Eraldi Compose installi ei vaja.
- **SQLcl**: kui otsealla laadimine `download.oracle.com`-ist on sinu jaoks blokeeritud, installi selle
  asemel ametlik [Oracle SQL Developer laiendus VS Code'ile](https://marketplace.visualstudio.com/items?itemName=Oracle.sql-developer) —
  see paketeerib nii SQLcl kui ka sobiva JDK, nii et eraldi Java installi ei vaja. Kasuta SQLcl käivitamiseks
  *just seda* paketeeritud Javat, mitte eraldi süsteemi JDK-d, et vältida versioonikonflikte.

</TabItem>
<TabItem label="macOS">

- **Konteinerimootor + Compose**: Podman Homebrew kaudu katab mõlemad — vaata täpseid käske
  [Podman on Mac juhendist](/products/uc-local-apex-dev/docs/other/podman-on-mac/).
- **SQLcl**: `brew install sqlcl` (samuti kaetud Podman on Mac juhendis).

</TabItem>
<TabItem label="Linux">

- **Konteinerimootor + Compose**: installi `docker` koos `docker compose` pluginaga, või `podman` koos
  `podman compose`-ga, oma distro paketihaldurist.
- **SQLcl**: [installi käsitsi või paketihalduri kaudu](https://pacesettergraam.wordpress.com/2025/02/21/installing-sqlcl-in-ubuntu-linux-on-oci/), nii et `sql` on `PATH`-il.

</TabItem>
</Tabs>

### Ettevõttespetsiifiline tarkvara ja õigused

:::note[Täida see privaatselt]
Mõned organisatsioonid nõuavad, et ülal loetletud tarkvara tellitaks sisemise iseteeninduskataloogi või
tellimistööriista kaudu (näiteks ServiceNow katalog, JIRA Service Desk päring või sisemine paketitellimuse
tööriist) otsealla laadimise asemel, või pakuvad sisemist alternatiivi mõnele ülal loetletud tööriistale
(näiteks teistsugune sertifikaadi väljastamise klient mkcerti asemel, või proxy-sõbralik SQLcl
tarnimisviis). **Selles avalikus repositooriumis ei nimetata teadlikult mitte ühtegi konkreetset
sisemist tööriista** — järgi sama mustrit, mida kasutab
[Ettevõtte peegli seadistuse mall](/products/uc-local-apex-dev/docs/getting-started/enterprise-mirror-template/),
ja hoia tegelikud tööriistanimed, tellimislingid ja ekraanipildid oma tiimi privaatses wikis või sisemises
repositooriumis.

Privaatne sisseelamisleht peaks kajastama vähemalt:

- Milliseid [Vajaliku tarkvara](#2-vajalik-tarkvara) tööriistu (kui üldse) tuleb tellida sisemise kataloogi kaudu, ja täpset tellimuse/toote nime
- Iga sisemist alternatiivi loetletud tööriistale ning selle hankimise/seadistamise viisi
- Eeldatavat kinnitamise/tarnimise aega
- Kellega ühendust võtta, kui tellimus on kinni jäänud
:::

## 3. Juurdepääs ja õigused

Konteineripiltide tõmbamine ja, kui kasutusel, sisemise APEX/patch peegli kättesaamine võib vajada
spetsiifilist võrgu- või kataloogigrupi õigust enne, kui esimene `install.sh` käivitamine õnnestub.

- **Konteineriregistri õigus** — kui tiim kasutab `IMAGE_SOURCE=company` (sisemine peegel
  `container-registry.oracle.com` asemel), kinnita IT-lt/tiimijuhilt, et sinu kasutajal on õigus sellest
  peeglist piltide tõmbamiseks. Vaata [Ettevõtte peegli seadistuse malli](/products/uc-local-apex-dev/docs/getting-started/enterprise-mirror-template/)
  üldise tõrkeotsingu voo jaoks (`404`/`407`/sertifikaadivead).
- **Võrgujuurdepääs** — sisemise registri või APEX/patch peegli saavutamiseks võib olla vajalik VPN või
  ettevõtte võrgus olemine.
- **Versioonihalduse (lähtekoodi) õigus** — juurdepääs sellele repositooriumile (ja, kui rakendub, sinu
  organisatsiooni fork'ile/peeglile sellest).

:::note[Täida see privaatselt]
Nagu tarkvara puhulgi, **ära lisa sellesse avalikku repositooriumisse tegelike Active Directory/IAM
gruppide nimesid.** Loetle oma privaatses wikis konkreetne(d) grupp(id), millesse uus tiimiliige tuleb
lisada (näiteks "registri pull-õiguse grupp `<registri-host>` jaoks") ja kes päringu kinnitab. See peegeldab
[Ettevõtte peegli seadistuse malli "Mis peab jääma privaatseks"](/products/uc-local-apex-dev/docs/getting-started/enterprise-mirror-template/#what-must-stay-private)
osa.
:::

## 4. Sammsammuline seadistus

Kui ülaltoodu on korras, vali allpool oma platvorm ja järgi seda kontrollnimekirja algusest lõpuni — igal
sakil on kõik vajalik olemas, seega ei peaks sakkide vahel liikuma.

<Tabs>
<TabItem label="Windows">

**0. Platvormi eeltööd (ainult Windows, tee see esimesena):**

- [ ] Installi [Podman Desktop](https://podman-desktop.io/) (**kohustuslik** — paketeerib Podman CLI ja seadistab WSL2 masina automaatselt)
- [ ] Installi [Ubuntu WSL2-le](https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/)
- [ ] Installi [SQLcl Ubuntu/WSL2-sse](https://pacesettergraam.wordpress.com/2025/02/21/installing-sqlcl-in-ubuntu-linux-on-oci/)
- [ ] Ava terminal **Ubuntu-on-WSL2 distro sees** (mitte PowerShell/cmd) kõikide allolevate käskude jaoks

**DB + ORDS (vaikimisi):**

- [ ] `git clone https://github.com/United-Codes/uc-local-apex-dev.git && cd uc-local-apex-dev`
- [ ] `chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh`
- [ ] `./install.sh` (genereerib `.env`, tõmbab pildid, käivitab konteinerid, installib APEX — vaata [Alustamine → Kiirseadistus](/products/uc-local-apex-dev/docs/getting-started/#quick-setup) täieliku ülevaate jaoks)
- [ ] Logi sisse APEX-i `http://localhost:8181/ords/apex`, workspace `INTERNAL`, kasutaja `ADMIN`, ja `.env`-i `ORACLE_PASSWORD` väärtusega
- [ ] Valikuline: lülita sisse HTTPS, seades `FORCE_SECURE="true"` `.env`-is enne `install.sh` käivitamist (vaata [SSL seadistust](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration))
- [ ] Valikuline: loo oma esimene skeem + workspace käsuga `./local-26ai.sh create-user <nimi>` — vaata [Kasutajate loomist](/products/uc-local-apex-dev/docs/getting-started/creating-users/)

**ADB Free (alternatiiv):**

- [ ] Samad clone + `chmod` sammud, mis ülal
- [ ] `./local-26ai.sh adb/start` — vaata [ADB Free](/products/uc-local-apex-dev/docs/getting-started/adb-free/) versiooniparameetrite ja nõuete jaoks
- [ ] Logi sisse APEX-i / Database Actions-isse `https://localhost:8443/`

</TabItem>
<TabItem label="macOS">

**0. Platvormi eeltööd (ainult macOS, tee see esimesena):**

- [ ] Installi [Homebrew](https://brew.sh/)
- [ ] Järgi [Podman macOS-il](/products/uc-local-apex-dev/docs/other/podman-on-mac/) juhendit: `brew install podman`, `brew install sqlcl`, seejärel `podman machine init`/`set`/`start` vähemalt 4GB RAM / 3 CPU-ga
- [ ] Lisa SQLcl oma `PATH`-ile, nagu kirjeldatud selles juhendis
- [ ] Käivita allolevad käsud oma tavalises Terminal/iTerm shellis

**DB + ORDS (vaikimisi):**

- [ ] `git clone https://github.com/United-Codes/uc-local-apex-dev.git && cd uc-local-apex-dev`
- [ ] `chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh`
- [ ] `./install.sh` (genereerib `.env`, tõmbab pildid, käivitab konteinerid, installib APEX — vaata [Alustamine → Kiirseadistus](/products/uc-local-apex-dev/docs/getting-started/#quick-setup) täieliku ülevaate jaoks)
- [ ] Logi sisse APEX-i `http://localhost:8181/ords/apex`, workspace `INTERNAL`, kasutaja `ADMIN`, ja `.env`-i `ORACLE_PASSWORD` väärtusega
- [ ] Valikuline: lülita sisse HTTPS, seades `FORCE_SECURE="true"` `.env`-is enne `install.sh` käivitamist (vaata [SSL seadistust](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration))
- [ ] Valikuline: loo oma esimene skeem + workspace käsuga `./local-26ai.sh create-user <nimi>` — vaata [Kasutajate loomist](/products/uc-local-apex-dev/docs/getting-started/creating-users/)

**ADB Free (alternatiiv):**

- [ ] Samad clone + `chmod` sammud, mis ülal
- [ ] `./local-26ai.sh adb/start` — vaata [ADB Free](/products/uc-local-apex-dev/docs/getting-started/adb-free/) versiooniparameetrite ja nõuete jaoks
- [ ] Logi sisse APEX-i / Database Actions-isse `https://localhost:8443/`

</TabItem>
<TabItem label="Linux">

**0. Platvormi eeltööd (ainult Linux, tee see esimesena):**

- [ ] Installi Docker või Podman oma distro paketihaldurist (VM-kihti ei vaja, konteinerid töötavad otse)
- [ ] Installi [SQLcl](https://pacesettergraam.wordpress.com/2025/02/21/installing-sqlcl-in-ubuntu-linux-on-oci/) ja veendu, et `sql` käsk on `PATH`-il
- [ ] Podmani puhul lülita sisse ka rootless API socket: `systemctl --user enable --now podman.socket`

**DB + ORDS (vaikimisi):**

- [ ] `git clone https://github.com/United-Codes/uc-local-apex-dev.git && cd uc-local-apex-dev`
- [ ] `chmod +x ./install.sh ./local-26ai.sh ./setup.sh ./scripts/*.sh`
- [ ] `./install.sh` (genereerib `.env`, tõmbab pildid, käivitab konteinerid, installib APEX — vaata [Alustamine → Kiirseadistus](/products/uc-local-apex-dev/docs/getting-started/#quick-setup) täieliku ülevaate jaoks)
- [ ] Logi sisse APEX-i `http://localhost:8181/ords/apex`, workspace `INTERNAL`, kasutaja `ADMIN`, ja `.env`-i `ORACLE_PASSWORD` väärtusega
- [ ] Valikuline: lülita sisse HTTPS, seades `FORCE_SECURE="true"` `.env`-is enne `install.sh` käivitamist (vaata [SSL seadistust](/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration))
- [ ] Valikuline: loo oma esimene skeem + workspace käsuga `./local-26ai.sh create-user <nimi>` — vaata [Kasutajate loomist](/products/uc-local-apex-dev/docs/getting-started/creating-users/)

**ADB Free (alternatiiv):**

- [ ] Samad clone + `chmod` sammud, mis ülal
- [ ] `./local-26ai.sh adb/start` — vaata [ADB Free](/products/uc-local-apex-dev/docs/getting-started/adb-free/) versiooniparameetrite ja nõuete jaoks
- [ ] Logi sisse APEX-i / Database Actions-isse `https://localhost:8443/`

</TabItem>
</Tabs>

:::tip[Tiimi ühtsed workspace'id]
Kui tiim soovib, et kõik jõuaksid seadistuse järel samade skeemide/workspace'ideni, vaata
[Post-Install seadistust](/products/uc-local-apex-dev/docs/getting-started/post-install/) — see võimaldab
defineerida `post-install.conf` faili, mida `install.sh` automaatselt käivitab.
:::

## 5. Igapäevane kasutus

Kõik skriptid käivitatakse `local-26ai.sh` wrapperi kaudu:

```bash
./local-26ai.sh <käsk> [argumendid]
./local-26ai.sh --help          # kõikide saadaolevate käskude nimekiri
```

Vaata täielikku nimekirja [Käskude viitest](/products/uc-local-apex-dev/docs/reference/commands/).

### AI koodiabilise kasutamine

Kuna igaüks skript on lihtne, dokumenteeritud shell-käsk, saab AI koodiabiline (nt GitHub Copilot Chat VS
Code'is) enda peale võtta enamiku igapäevastest keskkonna ülesannetest — kirjelda vaid, mida soovid,
tavakeeles:

| Mida sa kirjutad | Mida see käivitab |
|---|---|
| *"Loo uus skeem ja APEX workspace nimega `orders`, kompressiooniga."* | `./local-26ai.sh create-user orders --compress` |
| *"Varunda `orders` skeem enne, kui alustan refaktoreerimist."* | `./local-26ai.sh backup-user orders` |
| *"Lülita ORDS-ile sisse HTTPS enesele allkirjastatud sertifikaadiga."* | `./local-26ai.sh create-self-signed-certificates` (või sea `FORCE_SECURE="true"` ja käivita `install.sh` uuesti) |
| *"Kui palju andmebaasi ruumi kasutab `orders`?"* | `./local-26ai.sh used-space` |
| *"Kontrolli ORDS konteineri logisid vigade jaoks viimase 100 rea seas."* | `podman logs --tail 100 local-26ai-ords` (vaata [Jälgimist](#6-jälgimine--logid)) |
| *"Taaskäivita keskkond andmeid kaotamata."* | `./local-26ai.sh stop && ./local-26ai.sh start` |

See toimib kõige paremini, kui abilisel on repositoorium workspace'ina avatud, et ta saaks lugeda
`readme.md`-d, [`reference/commands`](/products/uc-local-apex-dev/docs/reference/commands/) lehte ja
skripte täpse kasutuse jaoks. See repo sisaldab ka `.agents/skills/` kausta — repole spetsiifilisi
teadmisfaile, mida abilised nagu GitHub Copilot automaatselt kasutavad, sealhulgas ruuter Oracle'i
enda ametlikele SQLcl, ORDS, APEX ja Database oskustele (`oracle-upstream-skills`) kõige jaoks, mis jääb
väljapoole selle repo enda skriptidest.

## 6. Jälgimine ja logid

Enne abi küsimist, kontrolli konteinerite olekut ja logisid ise — või palu AI abilisel seda teha:

- *"Kontrolli, kas `local-26ai` ja `local-26ai-ords` konteinerid on terved."*
- *"Vaata `local-26ai-ords` logisid ja ütle, miks APEX ei laadi."*
- *"Kui palju CPU-d/RAM-i kasutab andmebaasi konteiner praegu?"*

Täielikud käsud (mõlema stacki jaoks, Windows/WSL2, macOS ja Linuxi peal) on
[Konteineri ressursikasutuse jälgimises](/products/uc-local-apex-dev/docs/other/monitoring-resources/).

## 7. Peatamine, käivitamine, varundamine ja taaskäivitamine

| Tegevus | DB + ORDS | ADB Free | Andmete kadu? |
|---|---|---|---|
| Peata (säilita andmed) | `./local-26ai.sh stop` | `podman stop local-adb-free` | Ei |
| Käivita uuesti | `./local-26ai.sh start` | `podman start local-adb-free` (**ära** kasuta `adb/start` jätkamiseks — see loob konteineri uuesti) | Ei |
| Taaskäivita (rakenda konfiguratsiooni muudatused) | `./local-26ai.sh stop && ./local-26ai.sh start` | `podman restart local-adb-free` | Ei |
| Varunda skeem | `./local-26ai.sh backup-user <nimi>` | Kasuta Database Actions'i eksporti, või sama DataPump lähenemist konteineri sees | Ei (loob `.dmp` faili) |
| Varunda kõik | `./local-26ai.sh backup-all` | — | Ei |
| Täielik lähtestamine (kustuta ja loo uuesti) | `./local-26ai.sh dev/reset` | `./local-26ai.sh adb/stop --remove` ja seejärel `adb/start` | **Jah — kustutab kõik andmed** |

:::caution[Täielik lähtestamine kustutab andmed]
Täielik lähtestamine eemaldab andmebaasi köite (volume) täielikult. Varunda alati (`backup-all`/`backup-user`)
kõik vajalik enne. Vaata [Levinud ülesandeid](/products/uc-local-apex-dev/docs/getting-started/common-tasks/)
ja [Varundamist](/products/uc-local-apex-dev/docs/getting-started/backups/) täpsemate detailide jaoks, või
[ADB Free → Pausile panemist](/products/uc-local-apex-dev/docs/getting-started/adb-free/#pause-free-up-cpuram-without-losing-anything)
ressursside vabastamiseks *andmeid kaotamata*.
:::

## Järgmised sammud

- [Arhitektuuri ülevaade](/products/uc-local-apex-dev/docs/reference/architecture/) — kuidas konteinerid, köited ja paroolid omavahel sobituvad
- [Kasutajate loomine](/products/uc-local-apex-dev/docs/getting-started/creating-users/) — sinu esimene skeem + APEX workspace
- [Levinud ülesanded](/products/uc-local-apex-dev/docs/getting-started/common-tasks/) — SSL, lähtestamised ja teised igapäevased toimingud
- [KKK](/products/uc-local-apex-dev/docs/other/faq/)
