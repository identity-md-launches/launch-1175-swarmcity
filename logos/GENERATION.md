# Artwork record

Tool: built-in OpenAI image generation (`image_gen.imagegen`, gpt-image), reference-guided generation.

Reference: [creator's original logo](https://fxumiqjngmabtgvruvka.supabase.co/storage/v1/object/public/forum-attachments/posts/mv11egyv-0jmm5h.jpg).
The source was a 73x73 JPEG showing black concentric hexagons and a green center
on ivory. Its hive-core subject, geometry and palette guided all five options.

Five drafts were drawn in five generation calls, one for each required style.
All five are delivered; no rejected drafts or additional regeneration attempts
exist. The generated originals were 1254x1254 RGB images. They were resized with
Lanczos sampling to the required 1024x1024 PNGs; no logo shapes, letters, paint,
backgrounds or visual effects were drawn or edited in code. `artifacts/logo.png`
is a byte-identical copy of `logos/logo-2.png`.

The five 64-pixel images and their 32-pixel circular crops were visually
inspected against white and near-black surfaces. Every output has its own
opaque background. Option 2 was selected for the primary wallet artifact
because its broad silhouette and green center survive the smallest crop.
The other options are retained alternatives: the mascot has finer facial
features; the lettermark intentionally contains SC, which excludes it from the
text-free primary artifact; the minted badge's surface texture disappears at
32 pixels; and the meme has a busier silhouette. These are differences in
suitability for the primary artifact, not rejected deliverables.

## Final prompt set

Each call used the creator JPEG as `referenced_image_paths` and
`transparent_background: false`.

### 1 — Mascot

Use case: logo-brand. Generate one 1024x1024 square PNG logo, option 1 mascot, for SwarmCity. The attached/reference image is a tiny creator logo: warm ivory field, charcoal black concentric hexagons, and a vivid mint-green small central hexagonal dot. Preserve that hexagonal hive-core identity and strictly this ivory/near-black/bright mint-green palette. Reinterpret it as a charming original compact hexagonal hive robot mascot head with one large glowing green cyclops eye and two short geometric antennae, bold confident welcoming expression achieved only by geometric shapes. Head is a single bold black silhouette with one large green eye, ivory flat background fills all edges. Polished editorial illustration with exceptionally simple chunky forms, no tiny mechanical details. Close-up face occupies about 80% of square and is safe in a circular crop, no outer badge, rim, decorative frame or border. Visually legible at 64px on both light and dark surrounding UI. No words, letters, numbers, ticker, brands, watermark, copyrighted characters, or multiple logos. Use the supplied image as reference only, draw a new original mascot.

### 2 — Minimal geometric symbol

Use case: logo-brand. Draw a new original logo, option 2 MINIMAL GEOMETRIC SYMBOL for SwarmCity. Deliver a single square image intended as 1024x1024 PNG. Image 1 is the creator reference: charcoal black hexagon, vivid mint-green center on warm ivory. Preserve that subject and palette. Create one exceptionally bold solid charcoal BLACK HEXAGONAL HIVE CORE silhouette with a large vivid mint green hexagonal center, a single strong iconic geometry. The outer hexagon is a filled shape, not an enclosing line or a hollow outline or badge border. Mint core about one third of total mark width. One cut-away ivory angular facet can give a distinctive architectural city/hive feeling, but no tiny detail. Warm ivory/off-white opaque background goes all the way to all four square edges. Mark fills most of canvas, no added margins or framing, no inset panel, no shadow, no texture, no scene. Designed to remain a single clear bold symbol in a 32-pixel circular wallet icon, essential mark stays inside that crop. Flat colored fills, strong geometry with subtle crafted personality; prioritize instant recognition. No typography: absolutely no words, letters, ticker or numbers. No brands, watermark or copyrighted characters. Draw the complete image, never a contact sheet.

### 3 — Ticker lettermark

Use case: logo-brand. Draw option 3, bold SC LETTERMARK for SwarmCity, as one 1024x1024 square PNG logo. Image 1 is reference only: retain creator's near-black, warm ivory and vivid mint-green palette and hexagonal hive-core identity. Draw the two capital letters SC as a heavy custom geometric interlocking monogram, readable instantly as S C at only 64px. S on left warm ivory, C on right warm ivory, chunky angular hexagon-inspired cuts and blunt terminals; one vivid mint green hexagonal dot precisely inside the C counter recalls the reference's green central nucleus. The large letters form a compact connected single monogram. Use a solid near-black charcoal background filling the entire square. Huge glyphs with thick strokes, balanced optical spacing, graphic identity designer quality, flat ink-like finishes, no tiny honeycomb textures, no extra icon separate from the monogram, no badge or enclosing frame. Centered and circular-crop friendly. Must read on light and dark surrounding page because artwork has its own opaque charcoal field. Exact and only text: SC. Absolutely no dollar sign, words, numbers, other letters, watermark, real brands, people or copyrighted characters. One logo only, not a mockup or contact sheet.

### 4 — Minted emblem

Use case: logo-brand. Create one 1024x1024 square PNG, option 4 COIN / MINTED EMBLEM for SwarmCity. Image 1 is a creator reference consisting of black nested hexagons and a green central nucleus on warm ivory. Faithfully preserve its hexagonal subject and near-black / warm ivory / vivid mint green colors. Reimagine the reference as a beautifully minted solid hexagonal graphite coin, viewed almost head-on with only slight thickness visible at lower right. On its face a large raised ivory hexagonal relief encloses a single vivid mint-green enamel hexagonal nucleus. Thick clean relief, broad facets, restrained metallic lighting, bold high contrast and strong silhouette, no micro-engraving, no text on the rim. Solid warm ivory opaque full-bleed square background, tight product-like icon crop where the coin dominates about 85% of image. All critical design reads at 64px on both dark and light page surrounds. Keep it one single emblem, no pedestal, no props, no multiple coins, no decorative outer picture frame. No words, letters, ticker, currency symbols, numbers, dates, brands, faces or watermark. Palette stays warm ivory, near black and bright mint-green, no gold or silver.

### 5 — Illustrative meme

Use case: logo-brand. Draw option 5 LOUD ILLUSTRATIVE MEME logo for SwarmCity as one square 1024x1024 PNG. Image 1 is reference only: black nested hexagonal hive shape, green core and ivory background. Keep its near-black, warm ivory and electric mint-green colors, with no extra hues. Turn that original hexagonal hive-core into a hilariously overexcited angular cyclops mascot: enormous bright green single eye with black pupil, wildly cocked eyebrow, huge ivory toothy grin with only two big simplified teeth, slightly tilted near-black hexagonal head. Punchy hand-inked comic style, very thick black contours, exaggerated squash and stretch, original character not based on any existing franchise. One head is the unmistakable main mark, with only a few broad ivory/mint energy bolts behind its silhouette, big simple graphic forms rather than detailed scene. Electric mint-green solid opaque full-bleed background fills the square. Character occupies most of canvas, circular crop safe and readable at 64px against both light and dark surrounding surfaces. A loud fun internet meme with no caption. No words, letters, ticker, numbers, dollar signs, watermark, real people, brands or copyrighted characters. No frame or border, no small busy details, no scene, no contact sheet.
