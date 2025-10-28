//
//  ContentView.swift
//  Demo
//
//  Created by Daniel Saidi on 2025-09-30.
//

import DeckKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {

    @Namespace private var cardNamespace
    private let fullPool: [Hobby] = ContentView.loadSplitRailFullPool()

    @State private var allHobbies: [Hobby] = []
    @State private var middleDeck: [Hobby] = []
    @State private var activePair: [Hobby] = []
    @State private var leftCollection: [Hobby] = []
    @State private var rightCollection: [Hobby] = []
    @State private var selectedHobby: Hobby? = nil
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var activeDragCardId: String? = nil
    @State private var interactionLocked = false
    @State private var pendingResolutionEdges: [Edge] = []

    @StateObject private var favoriteContext = FavoriteContext<Hobby>()
    @StateObject private var shuffleAnimation = DeckShuffleAnimation(animation: .bouncy)
    private let lingerDuration: TimeInterval = 0.2
    private let autoMoveDelay: TimeInterval = 0.12
    private let horizontalSwipeThreshold: CGFloat = 80
    private let cardExitDistance: CGFloat = 260
    private let pairHorizontalSpacing: CGFloat = 220
    private let activePairScale: CGFloat = 0.5

    private static func loadSplitRailHobbies() -> [Hobby] {
        let characters = SplitRailLoader.loadCharacters()
        if characters.isEmpty {
            return Hobby.demoCollection
        }
        return characters.enumerated().map { index, character in
            character.asHobby(number: index + 1)
        }
    }
    
    private static func loadSplitRailFullPool() -> [Hobby] {
        let characters = SplitRailLoader.loadCharacters()
        if characters.isEmpty {
            return Hobby.demoCollection
        }
        return characters.enumerated().map { index, character in
            character.asHobby(number: index + 1)
        }
    }

    private func sampleTwenty(from pool: [Hobby]) -> [Hobby] {
        if pool.count <= 20 { return pool }
        return Array(pool.shuffled().prefix(20).enumerated().map { idx, hobby in
            // Re-number 1...20 for display consistency
            Hobby(number: idx + 1, name: hobby.name, color: hobby.color, text: hobby.text, imageName: hobby.imageName)
        })
    }

    private func initializeDeckIfNeeded() {
        guard allHobbies.isEmpty else { return }
        let sample = sampleTwenty(from: fullPool)
        allHobbies = sample
        configureDeck(with: sample, resetCollections: true)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let sideHeight = max(proxy.size.height * 0.26, 160)
                ZStack {
                    Color.background
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        HStack(spacing: 16) {
                            sortedCollectionView(
                                title: "Live",
                                systemImage: "arrowshape.turn.up.left",
                                collection: leftCollection,
                                isLeading: true,
                                accessibilityLabel: "Live collection area"
                            )
                            sortedCollectionView(
                                title: "Die",
                                systemImage: "arrowshape.turn.up.right",
                                collection: rightCollection,
                                isLeading: false,
                                accessibilityLabel: "Die collection area"
                            )
                        }
                        .frame(height: sideHeight)

                        deckArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding()
                }
            }
        }
        .onAppear { initializeDeckIfNeeded() }
        .navigationTitle("DeckKit")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(action: shuffle) { Image.shuffle }
                    .accessibilityLabel("Shuffle deck")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: toggleFavorites) { Image.favorite }
                    .tint(.red)
                    .symbolVariant(showOnlyFavorites ? .fill : .none)
                    .accessibilityLabel(showOnlyFavorites ? "Show all cards" : "Show only favorites")
            }
        }
        .sheet(item: $selectedHobby) { hobby in
            ZStack {
                Color.background.ignoresSafeArea()
                HobbyCard(
                    hobby: hobby,
                    isFavorite: favoriteContext.isFavorite(hobby),
                    isFlipped: false,
                    favoriteAction: favoriteContext.toggleIsFavorite
                )
                .padding()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .accessibilityAddTraits(.isModal)
        }
    }
}

private extension ContentView {

    var deckArea: some View {
        ZStack {
            DeckView(
                $middleDeck,
                shuffleAnimation: shuffleAnimation,
            ) { hobby in
                HobbyCard(
                    hobby: hobby,
                    isFavorite: favoriteContext.isFavorite(hobby),
                    isFlipped: shuffleAnimation.isShuffling,
                    favoriteAction: favoriteContext.toggleIsFavorite
                )
                .matchedGeometryEffect(id: hobby.id, in: cardNamespace)
                .opacity(activePair.contains(where: { $0.id == hobby.id }) ? 0 : 1)
            }
            .scaleEffect(0.9)
            .padding()
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if deckIsExhausted {
                allDoneView
            } else {
                activePairLayer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active deck")
        .accessibilityHint(deckAccessibilityHint)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: middleDeck)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activePair)
    }

    var deckIsExhausted: Bool {
        activePair.isEmpty && middleDeck.isEmpty
    }

    var hasSingleActiveCard: Bool {
        activePair.count == 1
    }

    var deckAccessibilityHint: String {
        hasSingleActiveCard
            ? "Swipe left to send the card to the left collection or right to send it to the right collection."
            : "Swipe either card left or right. The other card will move to the opposite side automatically."
    }

    var activePairLayer: some View {
        ZStack {
            ForEach(activePair) { hobby in
                activeCardView(for: hobby)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func activeCardView(for hobby: Hobby) -> some View {
        let role = activeRole(for: hobby)
        let baseOffset = offset(for: role)
        let currentOffset = dragOffsets[hobby.id] ?? .zero
        let rotation = rotation(for: role) + dragRotation(for: hobby)
        let isInteractable = !interactionLocked && (activeDragCardId == nil || activeDragCardId == hobby.id)
        let zIndex = activeDragCardId == hobby.id ? 3 : role.zIndex

        return HobbyCard(
            hobby: hobby,
            isFavorite: favoriteContext.isFavorite(hobby),
            isFlipped: shuffleAnimation.isShuffling,
            favoriteAction: favoriteContext.toggleIsFavorite
        )
        .matchedGeometryEffect(id: hobby.id, in: cardNamespace)
        .scaleEffect(activePairScale)
        .offset(
            x: baseOffset.width + currentOffset.width,
            y: baseOffset.height + currentOffset.height
        )
        .rotationEffect(.degrees(rotation))
        .shadow(color: Color.black.opacity(0.15), radius: 12, y: 8)
        .zIndex(zIndex)
        .gesture(dragGesture(for: hobby))
        .allowsHitTesting(isInteractable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(role.accessibilityLabel)
        .accessibilityHint(hasSingleActiveCard
            ? "Swipe left to send this card left or right to send it right."
            : "Swipe to send this card \(role.accessibilityDirectionDescription). The other card will move to the opposite side.")
    }

    private func activeRole(for hobby: Hobby) -> ActiveCardRole {
        guard activePair.count > 1 else { return .single }
        return activePair.first?.id == hobby.id ? .left : .right
    }

    private func offset(for role: ActiveCardRole) -> CGSize {
        switch role {
        case .left:
            return CGSize(width: -pairHorizontalSpacing / 2, height: 0)
        case .right:
            return CGSize(width: pairHorizontalSpacing / 2, height: 0)
        case .single:
            return .zero
        }
    }

    private func rotation(for role: ActiveCardRole) -> Double {
        return 0
    }

    func dragRotation(for hobby: Hobby) -> Double {
        guard let offset = dragOffsets[hobby.id] else { return 0 }
        let rotation = Double(offset.width / 20)
        return min(max(rotation, -12), 12)
    }

    private enum ActiveCardRole {
        case left
        case right
        case single

        var zIndex: Double {
            switch self {
            case .left: return 1
            case .right: return 2
            case .single: return 2
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .left: return "Active left card"
            case .right: return "Active right card"
            case .single: return "Active card"
            }
        }

        var accessibilityDirectionDescription: String {
            switch self {
            case .left, .right: return "left or right"
            case .single: return "left or right"
            }
        }
    }

    var allDoneView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("All done")
                .font(.title3)
                .fontWeight(.semibold)
            Text("You have sorted all cards.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityLabel("All done. You have sorted all cards.")
    }

    func sortedCollectionView(
        title: String,
        systemImage: String,
        collection: [Hobby],
        isLeading: Bool,
        accessibilityLabel: String
    ) -> some View {
        let alignment: HorizontalAlignment = isLeading ? .leading : .trailing
        return VStack(alignment: alignment, spacing: 12) {
            HStack(spacing: 8) {
                if isLeading {
                    Label(title, systemImage: systemImage)
                    Spacer(minLength: 0)
                    countBadge(count: collection.count)
                } else {
                    countBadge(count: collection.count)
                    Spacer(minLength: 0)
                    Label(title, systemImage: systemImage)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(collection.count) card\(collection.count == 1 ? "" : "s")")

            Group {
                if collection.isEmpty {
                    emptyCollectionView(isLeading: isLeading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(collection) { hobby in
                                sortedThumbnail(for: hobby)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Cards that have been swiped to the \(isLeading ? "left" : "right") side appear here.")
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: collection)
    }

    @ViewBuilder
    func countBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.1))
            )
            .accessibilityHidden(true)
    }

    func emptyCollectionView(isLeading: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: isLeading ? "arrow.left" : "arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Swipe \(isLeading ? "left" : "right") to add cards")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    func sortedThumbnail(for hobby: Hobby) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            Text(hobby.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
        }
        .matchedGeometryEffect(id: hobby.id, in: cardNamespace)
        .frame(width: 140, height: 90)
        .shadow(color: Color.black.opacity(0.1), radius: 6, y: 4)
        .onTapGesture {
            selectedHobby = hobby
        }
        .accessibilityLabel("\(hobby.name)")
    }

    var favoriteHobbies: [Hobby] {
        allHobbies.filter(isFavorite)
    }

    var showOnlyFavorites: Bool {
        favoriteContext.showOnlyFavorites
    }

    func isFavorite(_ hobby: Hobby) -> Bool {
        favoriteContext.isFavorite(hobby)
    }

    func dragGesture(for hobby: Hobby) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !interactionLocked else { return }
                if activeDragCardId == nil || activeDragCardId == hobby.id {
                    activeDragCardId = hobby.id
                    dragOffsets[hobby.id] = value.translation
                }
            }
            .onEnded { value in
                activeDragCardId = nil
                guard !interactionLocked else {
                    resetDrag(for: hobby)
                    return
                }
                dragEnded(for: hobby, value: value)
            }
    }

    func dragEnded(for hobby: Hobby, value: DragGesture.Value) {
        dragOffsets[hobby.id] = value.translation
        guard abs(value.translation.width) > horizontalSwipeThreshold else {
            resetDrag(for: hobby)
            return
        }
        let edge: Edge = value.translation.width > 0 ? .trailing : .leading
        resolvePair(swiped: hobby, edge: edge)
    }

    func resetDrag(for hobby: Hobby) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            dragOffsets[hobby.id] = .zero
        }
    }

    func resolvePair(swiped hobby: Hobby, edge: Edge) {
        guard edge == .leading || edge == .trailing else {
            resetDrag(for: hobby)
            return
        }
        guard activePair.contains(where: { $0.id == hobby.id }) else { return }

        interactionLocked = true

        let direction: CGFloat = edge == .leading ? -1 : 1
        let currentOffset = dragOffsets[hobby.id] ?? .zero
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            dragOffsets[hobby.id] = CGSize(
                width: currentOffset.width + direction * cardExitDistance,
                height: currentOffset.height
            )
        }

        if let otherCard = pairedCard(for: hobby) {
            scheduleAutoMove(for: otherCard, to: edge.opposite)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + lingerDuration) {
            moveActiveCard(hobby, to: edge)
        }
    }

    func scheduleAutoMove(for hobby: Hobby, to edge: Edge) {
        DispatchQueue.main.asyncAfter(deadline: .now() + autoMoveDelay) {
            let direction: CGFloat = edge == .leading ? -1 : 1
            let currentOffset = dragOffsets[hobby.id] ?? .zero
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                dragOffsets[hobby.id] = CGSize(
                    width: currentOffset.width + direction * cardExitDistance,
                    height: currentOffset.height
                )
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + lingerDuration) {
                moveActiveCard(hobby, to: edge)
            }
        }
    }

    func pairedCard(for hobby: Hobby) -> Hobby? {
        activePair.first { $0.id != hobby.id }
    }

    func moveActiveCard(_ hobby: Hobby, to edge: Edge) {
        guard let index = activePair.firstIndex(where: { $0.id == hobby.id }) else { return }
        let card = activePair.remove(at: index)
        dragOffsets.removeValue(forKey: card.id)
        pendingResolutionEdges.append(edge)

        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            switch edge {
            case .leading:
                leftCollection.append(card)
            case .trailing:
                rightCollection.append(card)
            default:
                break
            }
        }

        if activePair.isEmpty {
            announceResolution(for: pendingResolutionEdges)
            pendingResolutionEdges.removeAll()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                prepareActivePair()
            }
        }
    }

    func announceResolution(for edges: [Edge]) {
        guard !edges.isEmpty else { return }
#if canImport(UIKit)
        let uniqueEdges = Set(edges)
        let message: String
        if uniqueEdges.count >= 2 {
            message = "Sent one card to left and one to right."
        } else if let edge = edges.first {
            switch edge {
            case .leading: message = "Sent card to the left."
            case .trailing: message = "Sent card to the right."
            default: message = "Sent card."
            }
        } else {
            message = "Sent cards."
        }
        UIAccessibility.post(notification: .announcement, argument: message)
#endif
    }

    func prepareActivePair() {
        guard activePair.isEmpty else { return }
        guard !middleDeck.isEmpty else {
            interactionLocked = false
            return
        }
        let count = min(2, middleDeck.count)
        let newPair = Array(middleDeck.prefix(count))
        middleDeck.removeFirst(count)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            activePair = newPair
        }

        dragOffsets = newPair.reduce(into: [:]) { result, hobby in
            result[hobby.id] = .zero
        }
        interactionLocked = false
    }

    func configureDeck(with items: [Hobby], resetCollections: Bool, preparePair: Bool = true) {
        middleDeck = items
        activePair.removeAll()
        dragOffsets.removeAll()
        pendingResolutionEdges.removeAll()
        interactionLocked = false
        activeDragCardId = nil

        if resetCollections {
            leftCollection.removeAll()
            rightCollection.removeAll()
        }

        guard preparePair else { return }
        DispatchQueue.main.async {
            prepareActivePair()
        }
    }

    func shuffle() {
        let sample = sampleTwenty(from: fullPool)
        allHobbies = sample
        configureDeck(with: sample, resetCollections: true, preparePair: false)
        shuffleAnimation.shuffle($middleDeck, times: 5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            prepareActivePair()
        }
    }

    func toggleFavorites() {
        favoriteContext.showOnlyFavorites.toggle()
        let updatedDeck = showOnlyFavorites ? favoriteHobbies : allHobbies
        configureDeck(with: updatedDeck, resetCollections: true)
    }
}

private extension Edge {

    var opposite: Edge {
        switch self {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }
}

#Preview {
    ContentView()
}
