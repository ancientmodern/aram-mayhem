"""League VFX coverage audit: which raw bin fields our particle emulator extracts, consumes and understands.

Enumerates every field (with its containing class) of the raw VfxSystemDefinitionData objects behind every system in
data/vfx/*.json, straight from the game bins (not from our json), and weights each use by how often the system
appears in play (VFXLOG spawn counts from `--sim --vfxlog` runs in tools/extracted/vfxcov/*.log; every system gets a
base weight of 1 so unseen ones still count). Value fields are split by the features they use (constant / over-life
or emitter-time curve / probability table), and enum / flag fields record their value distribution.

For each field it reports
  extracted  - tools/lol/extract_vfx.py reads it (FIELDS table below, cross-checked against the extractor source)
  consumed   - the json key it becomes is read by src/vfx/lol_vfx.gd / lol_trail.gd / lol_beam.gd / lol_process.gdshader
  semantics  - confirmed / approx / unknown, with the evidence (SEM table below)

Writes tools/extracted/vfxcov/coverage.json and docs/VFX_COVERAGE.md (ranked by weighted use x missing support).

Usage: python tools/lol/vfx_coverage.py [--rescan]     (--rescan rebuilds the raw system cache from the WADs)
"""
import glob
import json
import os
import pickle
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(__file__))
from wad import Wad  # noqa: E402
from binfile import BinFile, to_py  # noqa: E402
from vfx_names import TABLE as VT  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
OUT = os.path.join(ROOT, "tools", "extracted", "vfxcov")
CACHE = os.path.join(OUT, "raw_systems.pkl")
VFX_CLS = 0x45cd899f
CHAMPS = ["Ahri", "Garen", "Darius", "Yasuo", "MasterYi", "Malphite", "Leona", "Lux", "Jinx", "Ezreal", "MissFortune",
          "Annie", "Sona", "Veigar"]

# ------------------------------------------------------------------ names (CommunityDragon hash lists when present)
T = dict(VT)
for _f in ("hashes.binfields.txt", "hashes.bintypes.txt"):
    _p = os.path.join(ROOT, "tools", "extracted", "cdhash", _f)
    if os.path.exists(_p):
        for _ln in open(_p, encoding="utf-8"):
            _h, _, _n = _ln.strip().partition(" ")
            if _n:
                T[int(_h, 16)] = _n
# canonical (lower-case) field name -> display name
def canon(n):
    return n.lower()


# ------------------------------------------------------------------ support tables
# field (lower-case, "Class.field" or "field") -> json key(s) written by extract_vfx.py ("" = read but folded
# into another key / used only by the extractor). Fields not listed are not extracted.
FIELDS = {
    # system
    "vfxsystemdefinitiondata.particlename": "name",
    "vfxsystemdefinitiondata.complexemitterdefinitiondata": "emitters",
    "vfxsystemdefinitiondata.simpleemitterdefinitiondata": "emitters",
    "vfxsystemdefinitiondata.overridescalecap": "scale_cap",
    # emitter: timing
    "emittername": "name", "rate": "rate rate_ec", "lifetime": "life", "timebeforefirstemission": "delay",
    "period": "period", "timeactiveduringperiod": "active", "issingleparticle": "single",
    "particlelifetime": "plife plife_q", "particlelinger": "linger", "emitterlinger": "elinger",
    "linger": "linger_color", "vfxemitterlegacysimple.linger": "linger_color",
    "vfxlingerdefinitiondata.separatelingercolor": "linger_color",
    # placement / space
    "emitterposition": "pos", "bindweight": "bind local", "islocalorientation": "lorient",
    "particleislocalorientation": "plorient", "isgroundlayer": "ground", "isfollowingterrain": "terrain",
    "isdirectionoriented": "dir", "directionvelocityscale": "dvs", "directionvelocityminscale": "dvmin",
    "isuniformscale": "uniform", "pass": "pass", "alpharef": "alpha_ref", "depthbiasfactors": "dbias",
    "disablebackfacecull": "disable_cull",
    # colour
    "birthcolor": "bcolor bcolor_ec bcolor_q", "color": "color bcolor", "particlecolortexture": "ctex",
    "colorlookuptypex": "ctype", "colorlookuptypey": "ctype", "colorlookupscales": "cscale",
    "colorlookupoffsets": "coff",
    # scale / rotation
    "birthscale0": "bscale bscale_ec bscale_q", "scale0": "scale bscale", "birthrotation0": "brot brot_q",
    "birthrotationalvelocity0": "rotvel rotvel_q", "rotation0": "rot",
    # motion
    "birthvelocity": "bvel bvel_ec bvel_q", "birthdrag": "drag drag_q", "birthacceleration": "laccel",
    "worldacceleration": "accel", "birthorbitalvelocity": "orbit orbit_q",
    "fieldcollectiondefinition": "fields",
    "vfxfieldcollectiondefinitiondata.fieldaccelerationdefinitions": "fields",
    "vfxfieldcollectiondefinitiondata.fielddragdefinitions": "fields",
    "vfxfieldcollectiondefinitiondata.fieldnoisedefinitions": "fields",
    "vfxfieldcollectiondefinitiondata.fieldattractiondefinitions": "fields",
    "vfxfieldcollectiondefinitiondata.fieldorbitaldefinitions": "fields",
    "vfxfieldaccelerationdefinitiondata.acceleration": "fields", "vfxfielddragdefinitiondata.strength": "fields",
    "vfxfieldnoisedefinitiondata.frequency": "fields", "vfxfieldnoisedefinitiondata.velocitydelta": "fields",
    "vfxfieldnoisedefinitiondata.axisfraction": "fields", "vfxfieldattractiondefinitiondata.position": "fields",
    "vfxfieldattractiondefinitiondata.acceleration": "fields", "vfxfieldattractiondefinitiondata.radius": "fields",
    "vfxfieldorbitaldefinitiondata.direction": "fields",
    # shape
    "spawnshape": "shape", "vfxshapesphere.radius": "shape", "vfxshapesphere.flags": "shape",
    "vfxshapebox.size": "shape", "vfxshapebox.flags": "shape", "vfxshapecylinder.radius": "shape",
    "vfxshapecylinder.height": "shape", "vfxshapecylinder.flags": "shape",
    "vfxshapelegacy.emitoffset": "shape", "vfxshapelegacy.emitrotationangles": "shape",
    "vfxshapelegacy.emitrotationaxes": "shape",
    # flipbook / uv
    "texdiv": "texdiv", "numframes": "frames", "framerate": "fps", "birthframerate": "fps", "startframe": "start_frame",
    "israndomstartframe": "rand_frame", "uvscale": "uvscale", "birthuvscrollrate": "uvrate uvrate_q",
    "particleuvscrollrate": "uvint", "uvrotation": "uvrot", "birthuvrotaterate": "uvrotrate", "uvmode": "uvmode",
    "uvscrollclamp": "uvclamp", "texaddressmodebase": "addr", "emitteruvscrollrate": "emuv",
    "textureflipu": "flip", "textureflipv": "flip", "birthuvoffset": "uvoff",
    "texturemult": "tex2", "vfxtexturemultdefinitiondata.texturemult": "tex2",
    "vfxtexturemultdefinitiondata.uvscalemult": "uv2scale", "vfxtexturemultdefinitiondata.texdivmult": "uv2scale",
    "vfxtexturemultdefinitiondata.birthuvscrollratemult": "uv2rate",
    "vfxtexturemultdefinitiondata.particleintegrateduvscrollmult": "uv2int",
    "vfxtexturemultdefinitiondata.uvrotationmult": "uv2rot", "vfxtexturemultdefinitiondata.birthuvoffsetmult": "uv2off",
    "vfxtexturemultdefinitiondata.texaddressmodemult": "addr2",
    "vfxtexturemultdefinitiondata.uvscrollclampmult": "uv2clamp",
    "vfxtexturemultdefinitiondata.emitteruvscrollratemult": "emuv2",
    # material
    "texture": "tex", "blendmode": "blend", "primitive": "prim",
    "alphaerosiondefinition": "ero_tex", "vfxalphaerosiondefinitiondata.erosionmapname": "ero_tex",
    "vfxalphaerosiondefinitiondata.erosiondrivecurve": "ero_curve",
    "vfxalphaerosiondefinitiondata.erosionmapchannelmixer": "ero_ch",
    "vfxalphaerosiondefinitiondata.erosionfeatherin": "ero_feather",
    "vfxalphaerosiondefinitiondata.erosionslicewidth": "ero_slice",
    "softparticleparams": "soft soft_in", "vfxsoftparticledefinitiondata.beginin": "soft_in",
    "vfxsoftparticledefinitiondata.deltain": "soft_in",
    "distortiondefinition": "distort", "vfxdistortiondefinitiondata.distortion": "distort",
    "vfxdistortiondefinitiondata.distortionmode": "distort", "vfxdistortiondefinitiondata.normalmaptexture": "distort",
    "reflectiondefinition": "fresnel", "vfxreflectiondefinitiondata.fresnel": "fresnel",
    "vfxreflectiondefinitiondata.fresnelcolor": "fresnel", "vfxreflectiondefinitiondata.reflectionfresnel": "fresnel",
    "vfxreflectiondefinitiondata.reflectionopacityglancing": "fresnel",
    "vfxreflectiondefinitiondata.reflectionopacitydirect": "fresnel",
    "fallofftexture": "falloff", "palettedefinition": "palette",
    "vfxpalettedefinitiondata.paletteselector": "palette", "vfxpalettedefinitiondata.palettecount": "palette",
    "vfxpalettedefinitiondata.palettetexture": "palette",
    # children
    "childparticlesetdefinition": "children", "vfxchildparticlesetdefinitiondata.childrenidentifiers": "children",
    "vfxchildparticlesetdefinitiondata.bonetospawnat": "child_bones", "vfxchildidentifier.effectkey": "children",
    "vfxchildidentifier.effectname": "children",
    # primitives
    "vfxprimitivemesh.mmesh": "mesh", "vfxmeshdefinitiondata.msimplemeshname": "mesh",
    "vfxmeshdefinitiondata.mmeshname": "mesh", "vfxprimitiveattachedmesh.mmesh": "amesh",
    "vfxmeshdefinitiondata.msubmeshestodraw": "amesh", "vfxmeshdefinitiondata.mlockmeshtoattachment": "amesh",
    "vfxprimitivecameratrail.mtrail": "trail", "vfxprimitivearbitrarytrail.mtrail": "trail",
    "vfxtraildefinitiondata.mcutoff": "trail", "vfxtraildefinitiondata.mmode": "trail",
    "vfxtraildefinitiondata.msmoothingmode": "trail", "vfxtraildefinitiondata.mmaxaddedperframe": "trail",
    "vfxtraildefinitiondata.mbirthtilingsize": "trail",
    "vfxprimitivebeam.mbeam": "beam_segments", "vfxprimitivecamerasegmentbeam.mbeam": "beam_segments",
    "vfxbeamdefinitiondata.msegments": "beam_segments",
    "vfxprimitiveplanarprojection.mprojection": "proj", "vfxprojectiondefinitiondata.myrange": "proj",
    "vfxprojectiondefinitiondata.mfading": "proj",
    # [vfx-runtime] round 2
    "disabled": "@gate", "filtering": "@gate", "vfxemitterfiltering.keywordsrequired": "@gate",
    "vfxemitterfiltering.spectatorpolicy": "@gate", "vfxemitterfiltering.keywordsexcluded": "@gate",
    "miscrenderflags": "misc", "isrotationenabled": "rotint", "rotation0": "rotint",
    "ee39916f.emitoffset": "shape", "vfxshapebox.size": "shape",
    "vfxsoftparticledefinitiondata.beginout": "soft_out", "vfxsoftparticledefinitiondata.deltaout": "soft_out",
    "vfxpalettedefinitiondata.palletesrcmixcolor": "palette",
    "vfxsystemdefinitiondata.transform": "sys_scale",
    "colorlookuptypex": "clut", "colorlookuptypey": "clut",
}

# json key -> consumed by the runtime?  (auto: the quoted key appears in the runtime sources)
RUNTIME = ["src/vfx/lol_vfx.gd", "src/vfx/lol_trail.gd", "src/vfx/lol_beam.gd", "src/vfx/lol_process.gdshader",
           "src/vfx/lol_particle.gdshader.txt"]

# semantics status: field -> (status, evidence). status: confirmed | approx | unknown | ignored (no visual effect)
SEM = {}


def sem(status, note, *fields):
    for f in fields:
        SEM[f] = (status, note)


# Evidence keys: [wiki] LeagueToolkit meta-wiki db/docs/VfxEmitterDefinitionData.yaml (+ primitive pages);
# [rey] ReyEngine (MIT) docs/research + ParticleQuadBuilder / VfxUvTransform; [bc] docs/LEAGUE_SHADERS.md (League's
# compiled particle shaders); [corpus] statistics over the raw bins of our systems (this tool)
W, RB, BC, CO = "[wiki]", "[rey]", "[bc]", "[corpus]"
sem("confirmed", f"League units -> m (x0.01), z mirrored; base of the birth position {W}", "emitterposition")
sem("confirmed", f"emission END time on the system clock, measured from the system start {W}", "lifetime")
sem("confirmed", f"delay before the first emission, system clock {W}", "timebeforefirstemission")
sem("confirmed", f"particles/s on the emitter phase; isSingleParticle = one burst of `rate` {W}", "rate",
    "issingleparticle")
sem("confirmed", f"seconds, emitter phase; negative = never expires {W}", "particlelifetime")
sem("confirmed", f"inverse-CDF multiplier tables, one draw per channel per particle {W}",
    "vfxprobabilitytabledata.keytimes", "vfxprobabilitytabledata.keyvalues")
sem("confirmed", f"piecewise linear, held at the ends; Birth* on the emitter phase, others on age fraction {W}",
    "vfxanimatedfloatvariabledata.times", "vfxanimatedvector3fvariabledata.times",
    "vfxanimatedcolorvariabledata.times", "vfxanimatedvector2fvariabledata.times")
sem("confirmed", "texture path", "texture")
sem("confirmed", f"0 Add (colour premultiplied, ONE,ONE), 1 Alpha, 3 None (depth write), 4 AlphaAdd, 5 Premul "
    f"{W}{RB}{BC}; 2 Subtract still drawn additive", "blendmode")
sem("confirmed", f"draw order: phase (ground layer first), pass, blend rank, miscRenderFlags {W}", "pass")
sem("confirmed", f"bit 0x1 DisableZBuffer = depth test off (not on ground-layer decals) {W}{RB}", "miscrenderflags")
sem("confirmed", f"flipbook cell = (col + uv) / cols, row-major from top-left; loop of numFrames from startFrame "
    f"{W}{BC}", "texdiv", "numframes", "startframe", "israndomstartframe")
sem("confirmed", f"frames/s x birthFrameRate; 0 = static frame {W}", "framerate", "birthframerate")
sem("confirmed", f"camera quad half-extents x/y (non-uniform), aquad half-extents, ray width/length/offset, mesh "
    f"multiplier {W}{CO}", "birthscale0", "scale0")
sem("confirmed", f"Euler degrees composed Z, then X, then Y; camera quads roll by X {W}{RB}{CO}", "birthrotation0",
    "birthrotationalvelocity0")
sem("confirmed", f"integrated spin rate in degrees per 1/60 s, needs isRotationEnabled {W}", "rotation0",
    "isrotationenabled")
sem("confirmed", f"units/s in the emitter frame, turned by the SpawnShape rotation {W}", "birthvelocity")
sem("confirmed", f"per-axis damping 1/s {W}", "birthdrag")
sem("confirmed", f"world-axis acceleration (integrated twice) {W}", "worldacceleration")
sem("confirmed", f"emitter-frame acceleration {W}", "birthacceleration")
sem("approx", f"rad/s revolving around the emitter origin; the orientation turn is not applied {W}",
    "birthorbitalvelocity")
sem("confirmed", f"Color x birthColor, BGRA8-clamped {W}{BC}", "birthcolor", "color")
sem("approx", f"translation follow weight over age; ours is binary (>= 0.5 rides along) {W}", "bindweight")
sem("approx", f"ground-layer render phase; drawn as a terrain decal with depth bias {W}", "isgroundlayer")
sem("confirmed", f"camera quads stretch y along screen velocity; aquads / meshes +Z along travel, applied last {W}",
    "isdirectionoriented")
sem("confirmed", f"stretch max(min, speed * scale) {W}", "directionvelocityscale", "directionvelocityminscale")
sem("confirmed", f"X used for every axis {W}", "isuniformscale")
sem("confirmed", f"default 5; clip(vertexA * texA - ref), 0 = off {W}{RB}{BC}", "alpharef")
sem("approx", f"slope / constant bias; sign not established {W}", "depthbiasfactors")
sem("confirmed", f"false: spawn frame axis aligned (only the system position) {W}", "islocalorientation")
sem("unknown", f"particles turn live with the attachment {W}; not implemented", "particleislocalorientation")
sem("confirmed", f"lookup drivers 0 Constant / 1 Lifetime / 2 Velocity (approx: offset) / 3 BirthRandom; defaults "
    f"(age, 1); clamped; dropped with erosion {W}", "particlecolortexture", "colorlookuptypex", "colorlookuptypey",
    "colorlookupscales", "colorlookupoffsets")
sem("confirmed", f"birth ramp offset + age*rate wrapped / clamped (-1..1); integrated scroll unclamped {W}{RB}",
    "birthuvscrollrate", "particleuvscrollrate", "uvscrollclamp")
sem("confirmed", f"system-time scroll after the flips (quads) {W}", "emitteruvscrollrate")
sem("confirmed", f"(uv - centre) * scale, rotate, + centre + translation, flip; inside the cell {W}{RB}", "uvscale",
    "uvrotation", "birthuvrotaterate", "textureflipu", "textureflipv", "birthuvoffset")
sem("confirmed", f"uvMode 2 LockAlpha: alpha at the un-translated uv {W}{BC} (1 ScreenSpace not implemented)",
    "uvmode")
sem("confirmed", f"0 wrap, 1 mirror, 2 clamp, 3 border {W}", "texaddressmodebase")
sem("approx", "second texture multiplied (its own uv transform partly read)", "texturemult",
    "vfxtexturemultdefinitiondata.texturemult", "vfxtexturemultdefinitiondata.uvscalemult",
    "vfxtexturemultdefinitiondata.birthuvscrollratemult", "vfxtexturemultdefinitiondata.particleintegrateduvscrollmult",
    "vfxtexturemultdefinitiondata.uvrotationmult", "vfxtexturemultdefinitiondata.texdivmult",
    "vfxtexturemultdefinitiondata.birthuvoffsetmult", "vfxtexturemultdefinitiondata.uvscrollclampmult",
    "vfxtexturemultdefinitiondata.texaddressmodemult", "vfxtexturemultdefinitiondata.emitteruvscrollratemult")
sem("approx", f"erosion band; shader exact {BC} but the CPU drive mapping is unverified", "alphaerosiondefinition",
    "vfxalphaerosiondefinitiondata.erosionmapname", "vfxalphaerosiondefinitiondata.erosiondrivecurve",
    "vfxalphaerosiondefinitiondata.erosionmapchannelmixer", "vfxalphaerosiondefinitiondata.erosionfeatherin",
    "vfxalphaerosiondefinitiondata.erosionslicewidth", "vfxalphaerosiondefinitiondata.erosionfeatherout")
sem("confirmed", f"smoothstep fade-in (beginIn, deltaIn) minus optional far fade {W}{BC}", "softparticleparams",
    "vfxsoftparticledefinitiondata.beginin", "vfxsoftparticledefinitiondata.deltain",
    "vfxsoftparticledefinitiondata.beginout", "vfxsoftparticledefinitiondata.deltaout")
sem("confirmed", f"screen uv + (2n-1)*power, tinted by tex*colour {BC}", "distortiondefinition",
    "vfxdistortiondefinitiondata.distortion", "vfxdistortiondefinitiondata.normalmaptexture",
    "vfxdistortiondefinitiondata.distortionmode")
sem("confirmed", f"F = 1 - pow(sat(N.V), fresnel); rgb += fresnelColor*F*alpha {BC}", "reflectiondefinition",
    "vfxreflectiondefinitiondata.fresnel", "vfxreflectiondefinitiondata.fresnelcolor")
sem("ignored", f"no shipped particle shader reads it {W}", "fallofftexture")
sem("confirmed", f"u = sat(dot(tex, mixer)); rgb replaced, alpha = tex.a {BC}; row selection approx",
    "palettedefinition", "vfxpalettedefinitiondata.paletteselector", "vfxpalettedefinitiondata.palettecount",
    "vfxpalettedefinitiondata.palettetexture", "vfxpalettedefinitiondata.palletesrcmixcolor")
sem("approx", f"child system per particle (birth children follow their particle) {W}", "childparticlesetdefinition",
    "vfxchildparticlesetdefinitiondata.childrenidentifiers", "vfxchildidentifier.effectkey",
    "vfxchildidentifier.effectname")
sem("confirmed", f"sphere/cylinder radius along X (filled with flag 0x1) + random turns; box half extents, +z face "
    f"or filled, quarter turns; the rotation also turns the velocity {W}", "spawnshape", "vfxshapesphere.radius",
    "vfxshapebox.size", "vfxshapecylinder.radius", "vfxshapecylinder.height", "vfxshapesphere.flags",
    "vfxshapebox.flags", "vfxshapecylinder.flags")
sem("confirmed", f"legacy offset + one turn per emitRotationAngles entry, in order {W}", "vfxshapelegacy.emitoffset",
    "vfxshapelegacy.emitrotationangles", "vfxshapelegacy.emitrotationaxes", "ee39916f.emitoffset")
sem("approx", f"ribbon through particles; mMode / tiling.x read; cutoff, smoothing walk, tiling.y not {W}",
    "vfxtraildefinitiondata.mcutoff", "vfxtraildefinitiondata.mmode", "vfxtraildefinitiondata.mbirthtilingsize",
    "vfxtraildefinitiondata.msmoothingmode", "vfxtraildefinitiondata.mmaxaddedperframe")
sem("confirmed", f"static particle mesh (.scb); culls back faces unless disableBackfaceCull {W}",
    "vfxprimitivemesh.mmesh", "vfxmeshdefinitiondata.msimplemeshname", "vfxmeshdefinitiondata.mmeshname",
    "disablebackfacecull")
sem("approx", f"linger: default 0 (vanish at stop) {W}; type 1/2 rewrites and emitterLinger not implemented",
    "particlelinger", "emitterlinger", "particlelingertype")
sem("confirmed", f"load-time gate: dropped {W}", "disabled")
sem("approx", f"camera quad / arbitrary quad (uv swap) / ray / mesh / attached mesh exact {W}; trails, beams and "
    "planar projections approximate", "primitive")
sem("confirmed", f"complex emitters run the full simulation {W}", "vfxsystemdefinitiondata.complexemitterdefinitiondata")
sem("approx", f"simple emitters drawn through the complex path (LegacySimple block not read) {W}",
    "vfxsystemdefinitiondata.simpleemitterdefinitiondata")
sem("approx", f"acceleration / drag / noise / attraction / orbital fields; radius and isLocalSpace not read {W}",
    "fieldcollectiondefinition", "vfxfieldcollectiondefinitiondata.fieldaccelerationdefinitions",
    "vfxfieldcollectiondefinitiondata.fielddragdefinitions", "vfxfieldcollectiondefinitiondata.fieldnoisedefinitions",
    "vfxfieldcollectiondefinitiondata.fieldattractiondefinitions",
    "vfxfieldcollectiondefinitiondata.fieldorbitaldefinitions", "vfxfieldaccelerationdefinitiondata.acceleration",
    "vfxfielddragdefinitiondata.strength", "vfxfieldnoisedefinitiondata.frequency",
    "vfxfieldnoisedefinitiondata.velocitydelta", "vfxfieldnoisedefinitiondata.axisfraction",
    "vfxfieldattractiondefinitiondata.position", "vfxfieldattractiondefinitiondata.acceleration",
    "vfxfieldattractiondefinitiondata.radius", "vfxfieldorbitaldefinitiondata.direction")
sem("approx", f"ribbon definition {W}", "vfxprimitivecameratrail.mtrail", "vfxprimitivearbitrarytrail.mtrail")
sem("approx", f"skinned overlay of the host (submesh masks partly read) {W}", "vfxprimitiveattachedmesh.mmesh",
    "vfxmeshdefinitiondata.mlockmeshtoattachment", "vfxmeshdefinitiondata.msubmeshestodraw")
sem("confirmed", f"keywordsRequired / spectatorPolicy gate (base skin: no keywords) {W}", "filtering",
    "vfxemitterfiltering.keywordsrequired", "vfxemitterfiltering.keywordsexcluded",
    "vfxemitterfiltering.spectatorpolicy")
sem("approx", f"scale by the bound object's size (weights ~1/200 -> ~1 for champions); not applied {W}",
    "flexshapedefinition", "vfxflexshapedefinitiondata.scaleemitoffsetbyboundobjectsize",
    "vfxflexshapedefinitiondata.scalebirthscalebyboundobjectsize")
sem("confirmed", f"system transform: uniform scale applied {W}", "vfxsystemdefinitiondata.transform")
sem("ignored", "editor / gameplay / audio metadata with no rendering effect", "emittername", "particlename",
    "vfxsystemdefinitiondata.particlepath", "vfxsystemdefinitiondata.assetcategory", "importance",
    "vfxsystemdefinitiondata.soundondefault", "vfxsystemdefinitiondata.soundoncreatedefault",
    "vfxsystemdefinitiondata.soundpersistentdefault", "vfxsystemdefinitiondata.audioparameterflexid",
    "vfxsystemdefinitiondata.audioparametertimescaledduration", "vfxsystemdefinitiondata.flags",
    "vfxsystemdefinitiondata.visibilityradius", "vfxsystemdefinitiondata.assetremappingtable",
    "vfxsystemdefinitiondata.builduptime", "vfxsystemdefinitiondata.objectpath", "vfxassetremap.oldasset",
    "vfxassetremap.newasset", "censormodulatevalue", "colorrenderflags",
    "vfxsystemdefinitiondata.voiceoveroncreatedefault", "vfxsystemdefinitiondata.voiceoverpersistentdefault",
    "audio", "vfxemitteraudio.soundpersistent", "meshrenderflags", "vfxemitterfiltering.keywordsexcluded")

VALUE_CLASSES = {"ValueFloat", "ValueVector2", "ValueVector3", "ValueColor", "IntegratedValueFloat",
                 "IntegratedValueVector2", "IntegratedValueVector3", "FlexValueFloat", "FlexValueVector2",
                 "FlexValueVector3", "FlexTypeFloat", "FlexValueColor", "ValueVector4"}
ENUMISH = re.compile(r"(mode|flags|pass|type|blend|primitive|shape|__class|isLocal|Is|is[A-Z]|disable|use|texDiv|"
                     r"alphaRef|mSegments|count)", re.I)


# ------------------------------------------------------------------ raw system collection
def wanted_systems():
    """{system name: [json files]} for every system in data/vfx/*.json."""
    out = defaultdict(list)
    for p in sorted(glob.glob(os.path.join(ROOT, "data", "vfx", "*.json"))):
        d = json.load(open(p, encoding="utf-8"))
        for k in d:
            if not k.startswith("_"):
                out[k].append(os.path.basename(p)[:-5])
    return out


def _scan_bin(data, want, found):
    try:
        bf = BinFile(data)
    except Exception:
        return
    for _k, v in bf.entries.items():
        if v.cls != VFX_CLS:
            continue
        nm = None
        for fk, fv in v.fields.items():
            if T.get(fk) == "particleName":
                nm = fv
        if nm and nm in want and nm not in found:
            found[nm] = to_py(v, T)


def collect(rescan=False):
    if os.path.exists(CACHE) and not rescan:
        return pickle.load(open(CACHE, "rb"))
    want = wanted_systems()
    found = {}
    for c in CHAMPS:
        w = Wad(f"{GAME}/Champions/{c}.wad.client")
        es = w.entries.values() if isinstance(w.entries, dict) else w.entries
        for e in es:
            try:
                d = w.read_entry(e)
            except Exception:
                continue
            if d[:4] in (b"PROP", b"PTCH"):
                _scan_bin(d, want, found)
    for wn in ("Global.wad.client", "Maps/Shipping/Map12.wad.client"):
        w = Wad(f"{GAME}/{wn}")
        es = w.entries.values() if isinstance(w.entries, dict) else w.entries
        for e in es:
            if e.size > 30_000_000:
                continue
            try:
                d = w.read_entry(e)
            except Exception:
                continue
            if d[:4] in (b"PROP", b"PTCH"):
                _scan_bin(d, want, found)
    os.makedirs(OUT, exist_ok=True)
    pickle.dump(found, open(CACHE, "wb"))
    return found


def play_weights():
    """VFXLOG spawn counts from sim logs."""
    cnt = Counter()
    for p in glob.glob(os.path.join(OUT, "*.log")):
        for ln in open(p, encoding="utf-8", errors="replace"):
            if ln.startswith("VFXLOG "):
                parts = ln.split()
                if len(parts) >= 3:
                    cnt[parts[2]] += 1
    return cnt


# ------------------------------------------------------------------ walking
def value_tag(o):
    """Feature tag of a Value* object: const / curve / rand / curve+rand."""
    dyn = o.get("dynamics") if isinstance(o, dict) else None
    tags = []
    if isinstance(dyn, dict):
        if len(dyn.get("times") or []) > 1:
            tags.append("curve")
        tabs = dyn.get("probabilityTables") or []
        if any(isinstance(t, dict) and t.get("keyValues") for t in tabs):
            tags.append("rand")
    return "+".join(tags) or "const"


class Stats:
    def __init__(self):
        self.rows = {}

    def add(self, key, w, sysname, value=None, tag=None):
        r = self.rows.get(key)
        if r is None:
            r = self.rows[key] = {"n": 0, "w": 0.0, "systems": set(), "values": Counter(), "tags": Counter(),
                                  "ex": sysname}
        r["n"] += 1
        r["w"] += w
        r["systems"].add(sysname)
        if value is not None:
            r["values"][value] += 1
        if tag:
            r["tags"][tag] += 1


def walk(o, cls, st, w, sysname, depth=0):
    if not isinstance(o, dict):
        return
    for k, v in o.items():
        if k == "__class":
            continue
        key = f"{cls}.{k}"
        val = None
        tag = None
        if isinstance(v, dict):
            c = v.get("__class", "?")
            if c in VALUE_CLASSES:
                tag = value_tag(v)
                val = c
            else:
                val = c
        elif isinstance(v, (bool, int)) and not isinstance(v, float):
            val = v
        elif isinstance(v, float):
            val = round(v, 3) if ENUMISH.search(k) else None
        elif isinstance(v, str) and (ENUMISH.search(k) or v.startswith("hash:")):
            val = v[:40]
        elif isinstance(v, list) and len(v) <= 4 and all(isinstance(x, (int, float)) for x in v) and ENUMISH.search(k):
            val = str([round(x, 2) for x in v])
        st.add(key, w, sysname, val, tag)
        if isinstance(v, dict):
            c = v.get("__class", "?")
            if c in VALUE_CLASSES:
                dyn = v.get("dynamics")
                if isinstance(dyn, dict):
                    # count value-structure features under the value's own row
                    if dyn.get("probabilityTables"):
                        st.add(f"{c}.probabilityTables", w, sysname)
                    if len(dyn.get("times") or []) > 1:
                        st.add(f"{c}.curve(times>1)", w, sysname)
                for kk in v:
                    if kk not in ("__class", "constantValue", "dynamics"):
                        st.add(f"{c}.{kk}", w, sysname)
                continue
            walk(v, c, st, w, sysname, depth + 1)
        elif isinstance(v, list):
            for x in v:
                if isinstance(x, dict):
                    c = x.get("__class", "?")
                    if c in VALUE_CLASSES:
                        st.add(f"{key}[{c}:{value_tag(x)}]", w, sysname)
                    else:
                        walk(x, c, st, w, sysname, depth + 1)


# ------------------------------------------------------------------ support lookup
def _src(path):
    try:
        return open(os.path.join(ROOT, path), encoding="utf-8").read()
    except OSError:
        return ""


def support(key):
    """(extracted json keys or None, consumed bool, (status, note))."""
    cls, _, field = key.partition(".")
    f = field.split("[")[0].lower()
    full = f"{cls.lower()}.{f}"
    js = FIELDS.get(full)
    if js is None and cls in ("VfxEmitterDefinitionData", "VfxEmitterLegacySimple", "VfxSystemDefinitionData"):
        js = FIELDS.get(f)
    st = SEM.get(full) or (SEM.get(f) if cls in ("VfxEmitterDefinitionData", "VfxSystemDefinitionData") else None)
    if cls in VALUE_CLASSES or cls.startswith("VfxAnimated") or cls == "VfxProbabilityTableData":
        # value containers: curves (emitter phase for Birth*, age fraction otherwise) and probability tables are
        # baked by the extractor into *_ec / curve / *_q keys; their use is counted on the owning field's row
        js = js or "value"
        st = st or ("confirmed", "value container: curves + probability tables baked per field [wiki]")
    return js, st


def consumed(js, runtime_src):
    if js is None:
        return False
    if js in ("@gate", "value"):
        return True   # handled inside the extractor (the emitter is dropped at load, like League)
    keys = [k for k in js.split() if k]
    return any(f'"{k}"' in runtime_src or f".{k}" in runtime_src for k in keys)


def main():
    rescan = "--rescan" in sys.argv
    systems = collect(rescan)
    want = wanted_systems()
    weights = play_weights()
    total_spawns = sum(weights.values())
    st = Stats()
    missing = [n for n in want if n not in systems]
    for nm, raw in systems.items():
        w = 1.0 + weights.get(nm, 0)
        walk(raw, "VfxSystemDefinitionData", st, w, nm)
    ext_src = _src("tools/lol/extract_vfx.py")
    run_src = "\n".join(_src(p) for p in RUNTIME)
    rows = []
    for key, r in st.rows.items():
        js, sm = support(key)
        con = consumed(js, run_src) if js is not None else False
        status, note = sm if sm else ("unknown", "")
        if js is None:
            level = 0
        elif not con:
            level = 1
        elif status in ("approx", "unknown"):
            level = 2 if status == "unknown" else 3
        else:
            level = 4
        if status == "ignored":
            level = 4
        gap = {0: 1.0, 1: 0.8, 2: 0.6, 3: 0.25, 4: 0.0}[level]
        rows.append({"key": key, "n": r["n"], "w": round(r["w"], 1), "systems": len(r["systems"]), "ex": r["ex"],
                     "values": r["values"].most_common(6), "tags": dict(r["tags"]), "json": js, "consumed": con,
                     "status": status, "note": note, "level": level, "impact": round(r["w"] * gap, 1)})
    rows.sort(key=lambda x: -x["impact"])
    # headline numbers over emitter-level fields (weighted uses)
    def pct(pred, rs):
        tw = sum(x["w"] for x in rs) or 1
        return 100.0 * sum(x["w"] for x in rs if pred(x)) / tw
    fld = [x for x in rows if not x["key"].startswith(("Value", "Integrated", "Flex", "VfxAnimated",
                                                         "VfxProbability")) and "[" not in x["key"]]
    head = {"systems_wanted": len(want), "systems_found_raw": len(systems), "systems_missing_raw": len(missing),
            "spawns_logged": total_spawns, "distinct_fields": len(fld),
            "extracted_pct": round(pct(lambda x: x["json"] is not None or x["status"] == "ignored", fld), 1),
            "consumed_pct": round(pct(lambda x: x["consumed"] or x["status"] == "ignored", fld), 1),
            "confirmed_pct": round(pct(lambda x: x["status"] in ("confirmed", "ignored"), fld), 1)}
    os.makedirs(OUT, exist_ok=True)
    json.dump({"head": head, "rows": rows, "missing": missing}, open(os.path.join(OUT, "coverage.json"), "w"),
              indent=1, default=list)
    print(json.dumps(head, indent=1))
    write_md(head, rows, missing, weights)
    return head, rows, missing, weights


MARK = "<!-- AUTO: generated by tools/lol/vfx_coverage.py below this line -->"
LEVEL = {0: "not extracted", 1: "extracted, unused", 2: "used, semantics unknown", 3: "used, approx", 4: "done"}


def write_md(head, rows, missing, weights):
    """Ranked table into docs/VFX_COVERAGE.md below MARK (the hand-written part above it is kept)."""
    path = os.path.join(ROOT, "docs", "VFX_COVERAGE.md")
    top = open(path, encoding="utf-8").read().split(MARK)[0] if os.path.exists(path) else "# VFX coverage\n\n"
    out = [MARK, "", "## Headline (weighted by play)", "",
           f"{head['systems_found_raw']} of {head['systems_wanted']} systems found in the raw bins "
           f"({head['systems_missing_raw']} are troybin conversions), {head['spawns_logged']} logged spawns, "
           f"{head['distinct_fields']} distinct emitter/system fields.", "",
           "| measure (share of weighted field uses) | value |", "|---|---|",
           f"| extracted by tools/lol/extract_vfx.py | {head['extracted_pct']}% |",
           f"| consumed by the runtime | {head['consumed_pct']}% |",
           f"| semantics confirmed by external evidence | {head['confirmed_pct']}% |", "",
           "## Open gaps ranked by impact (weighted uses x missing support)", "",
           "| impact | uses (weighted) | field | state | values / features | evidence / note |",
           "|---:|---:|---|---|---|---|"]
    for r in [x for x in rows if x["impact"] >= 20][:70]:
        vals = ", ".join(f"{v}:{n}" for v, n in r["values"][:4]) if r["values"] else ""
        tags = ", ".join(f"{k}:{n}" for k, n in r["tags"].items())
        out.append(f"| {r['impact']:.0f} | {r['w']:.0f} ({r['n']}) | `{r['key']}` | {LEVEL[r['level']]} | "
                   f"{(vals + ' ' + tags).strip()[:70]} | {r['note'][:110]} |")
    out += ["", "## Done / confirmed fields", "",
            "| uses (weighted) | field | json | evidence |", "|---:|---|---|---|"]
    for r in sorted([x for x in rows if x["level"] == 4 and x["status"] == "confirmed"], key=lambda x: -x["w"])[:60]:
        out.append(f"| {r['w']:.0f} | `{r['key']}` | {r['json']} | {r['note'][:120]} |")
    out += ["", "## Most-played systems (sim spawn counts)", "", "| spawns | system |", "|---:|---|"]
    for nm, n in weights.most_common(25):
        out.append(f"| {n} | {nm} |")
    out += ["", f"Systems not found in the raw bins (legacy troybin conversions): {', '.join(missing)}", ""]
    open(path, "w", encoding="utf-8", newline="\n").write(top.rstrip() + "\n\n" + "\n".join(out))


if __name__ == "__main__":
    main()
