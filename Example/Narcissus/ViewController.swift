//
//  ViewController.swift
//  Narcissus
//
//  Created by childc on 11/25/2019.
//  Copyright (c) 2019 childc. All rights reserved.
//

import UIKit
import AVFoundation

import Narcissus

class ViewController: UIViewController {
    private var narcissus = try? Narcissus()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func startButtonClick(_ sender: Any) {
        narcissus?.play()
    }
    
    @IBAction func stopButtonClick(_ sender: Any) {
        narcissus?.stop()
    }
}

