# Viper — Room to breathe

## Context and content truth
A single-page product website for Viper, a native SwiftUI Mac maintenance app. macOS 14+. Audience: discerning Mac owners and makers who want transparency over cleanup. Source facts: scan folders for large files, review and uninstall apps and associated data, find junk/leftovers, update apps/tools, discover and install apps, privacy settings shortcuts. Every destructive change is reviewed first. Cleanup moves selected files to Trash. No daemon, login item, telemetry or background polling. Do not invent testimonials, awards, prices, download numbers, speed improvements, or one-click automatic cleanup. Viper is not a security scanner. Distribution is currently source-based: primary CTA Get Viper scrolls to a section linking https://github.com/srikantmehra57/Viper with View source and build; never fabricate a binary download.

## Single style source and adaptation
Inspired by Superdesign library style animated-aurora-background-hero-dark-developer-tool-landing-page: near-black cinematic background, localized drifting light, tactile bright CTA, hairline glass product surface, disciplined typography. Adapt the palette to the actual Viper identity and omit the reference template's unrelated command bar, Windows CTA, generic badge, invented proof, and installation command. This is a product narrative, not a copy of the reference composition.

## Design tokens
Background #07070B. Surface #121219. Raised #1B1B24. Primary text #F4F4F7. Secondary text #9A9AAB. Hairline rgba(255,255,255,.10). Accent mint #6EE7B7 with teal #19B5A6. Secondary light lavender #9B8CFF and deep violet #6A4DFF, blue #6CB8FF. Warm amber #FFB547 only for meaningful UI categories. Typography: Inter sans-serif for all content; Geist Mono for restrained secondary metadata. Desktop hero 100–120px, weight 500, line-height 1.0, modest -0.055em tracking. Section headings 52–64px. Body 18–20px/1.6. Labels 14px. Metadata minimum 12px. Mobile hero 52–62px, section headings 36–42px, body 17px. Wide content max 1280px with 56px gutters desktop, 22px mobile. Spacing grid 8/16/24/32/48/64/96/128. Buttons 12px radius, cards 20px, generous voids instead of many boxes. No gratuitous pill clusters. Contrast must be high enough for legibility.

## Identity
Actual icon MUST render at logo positions, never substitute an invented mark or generic V glyph. Use https://vgbujcuwptvheqijyjbe.supabase.co/storage/v1/object/public/hmac-uploads/projects/b7f3cccc-2493-42b8-b457-8283eb391756/brand-assets/viper-app-icon/viper-icon.png alongside Viper wordmark.

## Composition
1. A refined horizontal header with icon and Viper wordmark, Explore / The experience / Philosophy, and Get Viper button.
2. An asymmetric two-column cinematic hero. Left: small NATIVE MAC CARE label, Your Mac. / Room to breathe. headline, two short lines explaining storage and cleanup with review; Get Viper CTA and Explore Viper text link. Right: sculptural spatial centerpiece, a live Three.js stack of translucent beveled square glass plates with a mint luminous core and sparse orbiting dust. Great visual scale, art direction and breathing space. Integrate a slim bottom metadata rail NATIVE BY DESIGN / macOS 14+ / QUIET BY NATURE. The object should react subtly to pointer, never block copy. A discreet pause motion control.
3. Large editorial heading Everything in its place. Feature index on left, active product panel on right. Tabs: Storage, Uninstaller, Junk & Leftovers, Updates, Discover. Show a designed interactive illustrative Viper UI (label Example preview); use meaningful sample folders/sizes and progress arcs. Tabs change title, description, visual content; controls cannot pretend to manipulate visitor's actual computer. Product UI uses actual theme, dark surfaces and lavender/mint accents.
4. Three steps across an airy ruled composition: Take a look. / Make the call. / Move on. Explain scan, review, Trash. Use giant quiet 01/02/03 indexes and fine rule connections, not three identical feature cards.
5. Philosophy section: Quiet by nature. Yours by design. Left large headline, right three concise rows: Runs when you ask; Review comes first; Nothing watching in the background. No fabricated trust marks.
6. Final centered invitation Give your Mac some room. Actual app icon above. Get Viper section states Source build, macOS 14 or later, Xcode required. View source and build link to the real GitHub repository. Minimal footer with Viper, macOS utility, Back to top.

## Motion and behavior
Live Three.js mesh: slow float/rotate, pointer parallax, pause control; cap pixel ratio and stop render loop when hidden/offscreen. Graceful fallback and prefers-reduced-motion. Sections reveal only progressively and remain visible without JS. Pointer hovers add subtle light. Smooth anchor nav. Functional responsive menu. Functional product tabs. No scroll hijacking or loading intro. Mobile stacks hero with a smaller artwork and keeps CTA in view. Keyboard focus visible. Buttons and links semantic and usable.

## Quality bar
A striking premium product website, not generic SaaS cards. Balance oversized editorial typography with a distinctive spatial scene, precise grids, and very spare copy. Every section should have its own composition while maintaining consistent rhythm. No external stock imagery. Do not invent award or originality claims.
