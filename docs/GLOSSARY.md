# Janus IADS - Glossary

| Term | Meaning |
|---|---|
| **IADS** | Integrated air-defence system: radars, missiles, guns and command posts working as one network instead of each site alone |
| **EW** | Early warning: a long-range search radar that sees aircraft far out but cannot guide missiles |
| **SAM** | Surface-to-air missile system. In Janus a SAM battery is one group: its radar(s) and launchers |
| **PD** | Point defence: short-range systems (Tor, Pantsir, C-RAM, Avenger) that protect a site or a base |
| **AAA** | Anti-aircraft artillery: guns |
| **C2 / command post** | Where the network is run from. Sites linked to it get its picture and its orders |
| **Relay** | A radio link that connects a far-away site to its command post (`COMMS` in Janus) |
| **Link** | A site's connection to its command post. Cut it (kill the post or the relay) and the site is on its own |
| **Autonomy** | What a site does when cut off: after a delay it searches with its own radar, on and off |
| **Picture** | Everything the network knows about aircraft in the air: the tracks |
| **Track** | One aircraft in the picture: where it is, where it is going, and, once identified, what it is |
| **Identification** | Knowing what an aircraft is (type, friend or foe). Weapons-tight networks only fire at identified tracks |
| **Cue** | The command post telling a site "target coming, radar on" |
| **EMCON** | Emission control: deciding which radars transmit and when. A radar that transmits can be found and attacked |
| **Dark** | A radar switched off to hide from attack |
| **WTA** | Weapon-target assignment: the network choosing which site engages which aircraft, so two sites do not waste missiles on one target while another gets through |
| **Pk** | Kill probability: Janus's estimate of how likely a site is to bring down a target, from range, altitude, crew and system |
| **Handoff** | Passing a target from one site to a better-placed one |
| **Weapons free / tight / hold** | Free: engage any enemy aircraft. Tight: only identified ones. Hold: no new engagements |
| **SEAD** | Suppression of enemy air defences: attacking radars and SAMs, usually with anti-radiation missiles |
| **ARM / HARM** | Anti-radiation missile: it flies down a radar's emissions. AGM-88 HARM, AGM-45 Shrike, Kh-58, Kh-31P, Kh-25MP, LD-10 |
| **Suppression** | Making radars go dark: even an ARM that misses has done its job if the SAM stopped shooting |
| **Flak trap** | Guns holding fire until aircraft are well inside their reach, then all opening up at once |
| **Doctrine** | The rules a side's network follows: who decides, how quickly crews act, when radars transmit, how they react to ARMs |
| **Crew tier** | GRN / REG / VET / ACE in a group name: how quick and good the crew is |
| **AWACS** | Airborne early warning aircraft (A-50, E-3, E-2): a radar in the sky, part of the picture |
| **GCI** | Ground-controlled interception: controllers vectoring fighters. Janus does not fly fighters; a GCI script can read Janus's picture |
| **MEZ / FEZ / JEZ** | Missile, fighter and joint engagement zones: airspace given to SAMs, to fighters, or shared |
| **Setup report** | What Janus writes to dcs.log at start: everything it found and what is wrong |
| **Check mode** | `CHECK_MODE = true`: the setup report on screen and the network drawn on the F10 map |
