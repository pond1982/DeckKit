//
//  ContentView.swift
//  Demo
//
//  Created by Daniel Saidi on 2025-09-30.
//

import DeckKit
import SwiftUI

struct ContentView: View {

    @State var allHobbies = Hobby.demoCollection
    @State var hobbies = Hobby.demoCollection

    @StateObject var favoriteContext = FavoriteContext<Hobby>()
    @StateObject var shuffleAnimation = DeckShuffleAnimation(animation: .bouncy)
    private let lingerDuration: TimeInterval = 4

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background
                    .ignoresSafeArea()
                
                DeckView(
                    $hobbies,
                    shuffleAnimation: shuffleAnimation,
                    swipeAction: { edge, hobby in
                        // Linger on top longer before advancing the deck
                        DispatchQueue.main.asyncAfter(deadline: .now() + lingerDuration) {
                            switch edge {
                            case .trailing, .leading:
                                // Advance the deck after the delay without showing a popup
                                hobbies.moveFirstItemToBack()
                            default:
                                break
                            }
                        }
                    }
                ) { hobby in
                    HobbyCard(
                        hobby: hobby,
                        isFavorite: favoriteContext.isFavorite(hobby),
                        isFlipped: shuffleAnimation.isShuffling,
                        favoriteAction: favoriteContext.toggleIsFavorite
                    )
                }
                .scaleEffect(0.85)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            }
            .navigationTitle("DeckKit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: shuffle) { Image.shuffle }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: toggleFavorites) { Image.favorite }
                        .tint(.red)
                        .symbolVariant(showOnlyFavorites ? .fill : .none)
                }
            }
        }
    }
}

private extension ContentView {

    var favoriteHobbies: [Hobby] {
        allHobbies.filter(isFavorite)
    }

    var showOnlyFavorites: Bool {
        favoriteContext.showOnlyFavorites
    }

    func isFavorite(_ hobby: Hobby) -> Bool {
        favoriteContext.isFavorite(hobby)
    }

    func shuffle() {
        allHobbies.shuffle()
        shuffleAnimation.shuffle($hobbies, times: 5)
    }

    func toggleFavorites() {
        favoriteContext.showOnlyFavorites.toggle()
        hobbies = showOnlyFavorites ? favoriteHobbies : allHobbies
    }
}

#Preview {
    ContentView()
}

