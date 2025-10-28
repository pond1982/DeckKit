//
//  ContentView.swift
//  Demo
//
//  Created by Daniel Saidi on 2025-09-30.
//

import DeckKit
import SwiftUI

struct ContentView: View {

    @Namespace private var cardNamespace

    @State private var allHobbies = Hobby.demoCollection
    @State private var middleDeck = Hobby.demoCollection
    @State private var leftCollection: [Hobby] = []
    @State private var rightCollection: [Hobby] = []
    @State private var selectedHobby: Hobby? = nil

    @StateObject private var favoriteContext = FavoriteContext<Hobby>()
    @StateObject private var shuffleAnimation = DeckShuffleAnimation(animation: .bouncy)
    private let lingerDuration: TimeInterval = 0.2

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
                                title: "Left Collection",
                                systemImage: "arrowshape.turn.up.left",
                                collection: leftCollection,
                                isLeading: true,
                                accessibilityLabel: "Left collection area"
                            )
                            sortedCollectionView(
                                title: "Right Collection",
                                systemImage: "arrowshape.turn.up.right",
                                collection: rightCollection,
                                isLeading: false,
                                accessibilityLabel: "Right collection area"
                            )
                        }
                        .frame(height: sideHeight)

                        deckArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding()
                }
            }
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
}

private extension ContentView {

    var deckArea: some View {
        ZStack {
            DeckView(
                $middleDeck,
                shuffleAnimation: shuffleAnimation,
                swipeAction: handleSwipe(edge:item:)
            ) { hobby in
                HobbyCard(
                    hobby: hobby,
                    isFavorite: favoriteContext.isFavorite(hobby),
                    isFlipped: shuffleAnimation.isShuffling,
                    favoriteAction: favoriteContext.toggleIsFavorite
                )
                .matchedGeometryEffect(id: hobby.id, in: cardNamespace)
            }
            .scaleEffect(0.9)
            .padding()
            .allowsHitTesting(!middleDeck.isEmpty)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Active deck")
            .accessibilityHint("Swipe left to send a card to the left collection or right to send it to the right collection.")

            if middleDeck.isEmpty {
                allDoneView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: middleDeck)
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

    func handleSwipe(edge: Edge, item hobby: Hobby) {
        guard edge == .leading || edge == .trailing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + lingerDuration) {
            moveFromDeck(hobby, to: edge)
        }
    }

    func moveFromDeck(_ hobby: Hobby, to edge: Edge) {
        guard let index = middleDeck.firstIndex(where: { $0.id == hobby.id }) else { return }
        let card = middleDeck.remove(at: index)
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
    }

    func shuffle() {
        allHobbies.shuffle()
        leftCollection.removeAll()
        rightCollection.removeAll()
        middleDeck = allHobbies
        shuffleAnimation.shuffle($middleDeck, times: 5)
    }

    func toggleFavorites() {
        favoriteContext.showOnlyFavorites.toggle()
        let updatedDeck = showOnlyFavorites ? favoriteHobbies : allHobbies
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            middleDeck = updatedDeck
            leftCollection.removeAll()
            rightCollection.removeAll()
        }
    }
}

#Preview {
    ContentView()
}
