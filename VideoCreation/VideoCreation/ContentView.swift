//
//  ContentView.swift
//  VideoCreation
//
//  Created by Siju Karunakaran on 29/07/23.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @State var url: URL? = nil
    var body: some View {
        VStack {
            if let url = self.url {
                let player = AVPlayer(url: url)
                VideoPlayer(player: player)
                    .onAppear{
                        player.play()
                    }
            }
            else {
                ProgressView()
            }
        }
        .padding()
        .onAppear{
            VideoRenderer.shared.renderVideo(withText: "Created by Siju Karunakaran",
                                        duration: 3.0) { url in
                guard let url = url else {
                    print("no url")
                    return
                }
                self.url = url
                print(url)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
