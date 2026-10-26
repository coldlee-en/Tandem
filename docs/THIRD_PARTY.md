# Third-party source and notices

Tandem's new code is AGPL-3.0-or-later. Native dependencies are fetched separately
and retain their own licenses. No Nintendo ROM, firmware, encryption key, or
system image is included.

| Project | Use | License information |
| --- | --- | --- |
| [Cytrus](https://github.com/folium-app/Cytrus) | iOS 3DS core | Upstream GPLv3 license; includes Azahar/Citra GPLv2-or-later source notices. |
| [Folium](https://github.com/folium-app/Folium) | Pinned dependency artifacts and Cytrus submodule | Preserve upstream license and individual artifact notices. No Folium frontend source is copied into Tandem. |
| [SharedDependencies](https://github.com/folium-app/SharedDependencies) | Cytrus C/C++ dependencies | Each bundled source/library retains its own notices. |
| [MeloNX fork](https://github.com/AzureDominus/melonx) | iOS Switch NativeAOT core | Pin declares AGPLv3-or-later. Exact license file, including prior licensing text, is in LICENSES/MeloNX-upstream.txt. |
| [Ryujinx](https://github.com/ryujinx-mirror/ryujinx) lineage | MeloNX foundation | MIT for original Ryujinx components, as documented by the fork. |
| MoltenVK, SDL, FFmpeg, Boost, zstd and transitive dependencies | Graphics, audio/video, utilities | Preserve the exact dependency versions' licenses/notices. FFmpeg build configuration determines applicable obligations. |

The setup scripts retain the source checkouts and Tandem's patches. The Switch
builder copies upstream notices to Frameworks/Notices, included in the native
app's resources. Copies of the reviewed Cytrus and MeloNX notices are also
included under LICENSES. Distribution must include the applicable notices and
corresponding source, including patches and build scripts, as required by those
licenses. Preserve the upstream source checkouts when preparing a release.

The scripts build an experimental development integration. They do not establish
that every historical third-party binary artifact is available or suitable for
redistribution in a particular product.
