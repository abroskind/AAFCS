//
//  ContentView.swift
//  AAFCS
//
//  Created by Dmytro Abroskin on 13/09/2023.
//


import SwiftUI
import SpriteKit

struct ContentView: View {
    var scene: SKScene {
        let scene = HUDScene(size:CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
        scene.scaleMode = .fill
        scene.backgroundColor = .clear
        return scene
    }
    
    
    var body: some View {
        let vc = HostedViewController()
            .ignoresSafeArea()
        SpriteView(scene: scene,options: [.allowsTransparency])
            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
            .ignoresSafeArea()
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
