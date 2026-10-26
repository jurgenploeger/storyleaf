import SwiftUI

/// Name, gender, hairstyle, and hair, outfit and skin colours, with a turning live preview, when a
/// hero is made. After that a barber in any town changes the hair (`BarberPanel`); the rest stays.
/// Every look is open from the start.
struct LookEditor: View {
    @Binding var name: String
    @Binding var look: Look
    /// Which race's walk sheet to preview.
    var raceID = "human"

    private var options: AppearanceOptions { Content.shared.appearance }
    private var race: RaceDef { Content.shared.race(raceID) }

    var body: some View {
        AdaptiveStack(spacing: 16) {
            VStack(spacing: 6) {
                TurntablePreview(look: look, race: race)
                Button {
                    look = Look(
                        hair: options.hair.randomElement()?.id ?? look.hair,
                        outfit: options.outfits.randomElement()?.id ?? look.outfit,
                        skin: options.skin.randomElement()?.id ?? look.skin,
                        gender: look.gender,
                        style: options.styles(for: race.sheet(for: look.gender)).randomElement()?.id ?? look.style
                    )
                } label: {
                    Label(L("Surprise me"), icon: .dice)
                }
                .buttonStyle(PixelButtonStyle(compact: true))
            }
            .frame(minWidth: 170)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Name")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                    TextField(L("Name"), text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(HUDStyle.font(15))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
                        .onChange(of: name) { _, value in
                            if value.count > 12 { name = String(value.prefix(12)) }
                        }
                }
                GenderPicker(genders: options.genders, selection: $look.gender)
                StylePicker(look: $look, race: race)
                SwatchPicker(title: L("Hair"), presets: options.hair, selection: $look.hair)
                SwatchPicker(title: L("Outfit"), presets: options.outfits, selection: $look.outfit)
                SwatchPicker(title: L("Skin"), presets: options.skin, selection: $look.skin)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The hero slowly turning on the spot, so you see the look from every side.
struct TurntablePreview: View {
    let look: Look
    let race: RaceDef
    var size: CGFloat = 164
    private let order: [Direction] = [.down, .right, .up, .left]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.9)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.9) % order.count
            Image(uiImage: ArtLibrary.shared.preview(from: race.sheet(for: look.gender), recolor: GameSession.rules(for: look), key: look.key,
                                                     facing: order[step], layers: GameSession.layers(race: race, look: look)))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.08)))
                .overlay(alignment: .bottom) {
                    Ellipse().fill(.black.opacity(0.2)).frame(width: size * 0.37, height: size * 0.07).offset(y: -size * 0.05)
                }
        }
        .accessibilityLabel(L("Preview of your hero"))
    }
}

/// Male or female: which of the race's walk sheets the hero uses. (A save from when there was a
/// third shows the first as picked; its hero keeps the race's own sheet.)
private struct GenderPicker: View {
    let genders: [GenderOption]
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("Gender")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            HStack(spacing: 8) {
                let current = genders.contains { $0.id == selection } ? selection : genders.first?.id
                ForEach(genders) { gender in
                    let selected = gender.id == current
                    Button(gender.name) { selection = gender.id }
                        .buttonStyle(PixelButtonStyle(tint: selected ? HUDStyle.gold : HUDStyle.dim, compact: true))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// Hairstyles, each shown on your hero as they look right now: the walk sheet's own hair first (a
/// gender's ponytail or braids), then every other, the other gender's included.
struct StylePicker: View {
    @Binding var look: Look
    let race: RaceDef

    private var styles: [HairStyle] { Content.shared.appearance.styles(for: race.sheet(for: look.gender)) }
    private var current: String { GameSession.style(for: look, race: race) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(L("Hairstyle")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                Text(styles.first { $0.id == current }?.name ?? "").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
            }
            // Every style suits everyone now (nine and counting), more than fit across: the row
            // scrolls, like the colours below, and opens on the one you're wearing.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(styles) { style in
                            let selected = style.id == current
                            Button {
                                look.style = style.id
                            } label: {
                                Image(uiImage: portrait(style))
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(selected ? HUDStyle.gold : .white.opacity(0.4), lineWidth: selected ? 3 : 1.5))
                                    .padding(2)
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(L("Hairstyle {style}", ["style": style.name]))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .id(style.id)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
        }
    }

    private func portrait(_ style: HairStyle) -> UIImage {
        var styled = look
        styled.style = style.id
        return ArtLibrary.shared.preview(from: race.sheet(for: look.gender), recolor: GameSession.rules(for: styled), key: styled.key,
                                         layers: GameSession.layers(race: race, look: styled))
    }
}

struct SwatchPicker: View {
    let title: String
    let presets: [LookPreset]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                Text(presets.first { $0.id == selection }?.name ?? "").font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        let selected = preset.id == selection
                        Button {
                            selection = preset.id
                        } label: {
                            Circle()
                                .fill(Color(uiColor: UIColor(hex: preset.swatch) ?? .white))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                                .overlay(Circle().strokeBorder(selected ? HUDStyle.gold : .clear, lineWidth: 3).padding(-4))
                                .overlay {
                                    if selected {
                                        IconImage(.check, size: 13).foregroundStyle(HUDStyle.ink)
                                    }
                                }
                                .padding(4)
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("\(title) \(preset.name)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// Rename a companion. (Its colours come from its species: rarer variants look different.)
struct CompanionEditor: View {
    let session: GameSession
    let pet: Pet
    let onDone: () -> Void
    @State private var name: String

    init(session: GameSession, pet: Pet, onDone: @escaping () -> Void) {
        self.session = session
        self.pet = pet
        self.onDone = onDone
        _name = State(initialValue: pet.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SpriteImage(art: session.artID(for: pet), size: 80)
                    .background(Circle().fill(.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Name")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                    TextField(L("Name"), text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(HUDStyle.font(14))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            }
            HStack {
                Button(L("Cancel"), action: onDone)
                    .buttonStyle(PixelButtonStyle(compact: true))
                Spacer()
                Button(action: save) {
                    Label(L("Save"), icon: .check)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
    }

    private func save() {
        session.renamePet(pet.id, to: name)
        onDone()
    }
}
