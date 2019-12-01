//
//  Narcissus.swift
//  Narcissus
//
//  Created by childc on 2019/11/27.
//

import Foundation
import AVFoundation
import AudioUnit

public class Narcissus {
    private let captureEngine = AVAudioEngine()
    private let recordEngine = AVAudioEngine()
    private let playEngine = AVAudioEngine()
    
    private var audioFormat: AVAudioFormat?
    private var audioUnit: AudioUnit?
    private var audioRenderer = AudioRenderer()
    private var audioCapturer = AudioCapturer()
    
    private let playFilePlayer = AVAudioPlayerNode()
    private let recordFilePlayer = AVAudioPlayerNode()
    private var playAudioFile: AVAudioFile?
    
    #if DEBUG
    private var capturedData = Data()
    #endif
    
    private struct AudioRenderer {
        var bufferList: AudioBufferList?
        var renderBlock: AVAudioEngineManualRenderingBlock?
    }
    
    private struct AudioCapturer {
        var bufferList: AudioBufferList?
//        var mixedBufferList: AudioBufferList?
        var audioUnit: AudioUnit?
        var renderBlock: AVAudioEngineManualRenderingBlock?
        
        #if DEBUG
        var inputData = Data()
        var renderedData = Data()
        #endif
    }
    
    public init(inputFormat: AVAudioFormat? = nil) throws {
        audioFormat = inputFormat ?? AVAudioFormat(commonFormat: MicInputConst.defaultFormat,
                                                   sampleRate: MicInputConst.defaultSampleRate,
                                                   channels: MicInputConst.defaultChannelCount,
                                                   interleaved: MicInputConst.defaultInterLeavingSetting)!
        
        print("audioFormatDesc: \(audioFormat!.streamDescription)")
        
        guard let playFileName = Bundle.main.url(forResource: "mixLoop", withExtension: "caf"),
            let playAudioFile = try? AVAudioFile(forReading: playFileName) else { return }
        self.playAudioFile = playAudioFile
        
//        try setupRecordEngine()
        try setupPlayEngine()
        try setupAudioUnit()
        
        let status: OSStatus = AudioOutputUnitStart(audioUnit!)
        guard status == 0 else {
            print("audio unit start failed...")
            return
        }
    }
    
    private func setupRecordEngine() throws {
        // Switch to manual rendering mode
        recordEngine.stop()
        try recordEngine.enableManualRenderingMode(.realtime, format: audioFormat!, maximumFrameCount: 10240)
        recordEngine.connect(recordEngine.inputNode, to: recordEngine.mainMixerNode, format: audioFormat!)
        
        audioCapturer.bufferList = AudioBufferList()
        audioCapturer.bufferList?.mNumberBuffers = 1
        audioCapturer.bufferList?.mBuffers.mNumberChannels = 1
        
//        audioCapturer.mixedBufferList = AudioBufferList()
//        audioCapturer.mixedBufferList?.mNumberBuffers = 1
//        audioCapturer.mixedBufferList?.mBuffers.mNumberChannels = 1
//        audioCapturer.mixedBufferList?.mBuffers.mDataByteSize = 0
//        audioCapturer.mixedBufferList?.mBuffers.mData = malloc(1024 * 2)
        
        recordEngine.inputNode.setManualRenderingInputPCMFormat(audioFormat!) { [weak self] (frameCnt) -> UnsafePointer<AudioBufferList>? in
            guard let audioBufferList = self?.audioCapturer.bufferList else { return nil }
            
            let audioCapacity = Int(audioBufferList.mBuffers.mDataByteSize)
            guard 0 < audioCapacity else { return nil }
            
            #if DEBUG
            if let ptrData = audioBufferList.mBuffers.mData?.bindMemory(to: UInt8.self, capacity: audioCapacity) {
                print("input data appended. size: \(audioCapacity)")
                self?.audioCapturer.inputData.append(ptrData, count: audioCapacity)
            }
            #endif
            
            var buffer = AudioBuffer()
            buffer.mDataByteSize = audioBufferList.mBuffers.mDataByteSize
            buffer.mData = audioBufferList.mBuffers.mData
            var bufferList = AudioBufferList(mNumberBuffers: audioBufferList.mNumberBuffers, mBuffers: (buffer))
            
            self?.audioCapturer.bufferList?.mBuffers.mData = nil
            self?.audioCapturer.bufferList?.mBuffers.mDataByteSize = 0
            
            return UnsafePointer<AudioBufferList>(&bufferList)
        }
        audioCapturer.renderBlock = recordEngine.manualRenderingBlock
        
        try recordEngine.start()
        
    }
    
    private func setupPlayEngine() throws {
        // Switch to manul rendering mode
        playEngine.stop()
        try playEngine.enableManualRenderingMode(.realtime, format: audioFormat!, maximumFrameCount: 10240)
        
        guard let playAudioFile = playAudioFile else { return }
//        let reverb = AVAudioUnitReverb()
//        reverb.loadFactoryPreset(.mediumHall)
//        reverb.wetDryMix = 50
//
//        playEngine.attach(reverb)
        playEngine.attach(playFilePlayer)
//        playEngine.connect(playFilePlayer, to: reverb, format: playAudioFile.processingFormat)
        playEngine.connect(playFilePlayer, to: playEngine.mainMixerNode, format: playAudioFile.processingFormat)
        playEngine.inputNode.setManualRenderingInputPCMFormat(audioFormat!) { [weak self] (frameCnt) -> UnsafePointer<AudioBufferList>? in
            guard var audioBufferList = self?.audioRenderer.bufferList else { return nil }
            return UnsafePointer<AudioBufferList>(&audioBufferList)
        }
        audioRenderer.renderBlock = playEngine.manualRenderingBlock
        
        try playEngine.start()
    }
    
    private func setupAudioUnit() throws {
        var audioUnitDescription = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_VoiceProcessingIO, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        
        guard let audioComponent = AudioComponentFindNext(nil, &audioUnitDescription) else {
            throw MicInputError.audioFormatError
        }

        AudioComponentInstanceNew(audioComponent, &audioUnit)
        
        var state: OSStatus = 0
        var enableOutput: UInt32 = 1
        state = AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enableOutput, UInt32(MemoryLayout<UInt32>.size))
        guard state == 0 else { throw MicInputError.audioFormatError }
        
        guard let streamDescription = audioFormat?.streamDescription else { throw MicInputError.audioFormatError }

        state = AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, streamDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard state == 0 else { throw MicInputError.audioFormatError }

        var enableInput: UInt32 = 1
        state = AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableInput, UInt32(MemoryLayout<UInt32>.size))
        guard state == 0 else { throw MicInputError.audioFormatError }

        state = AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, streamDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard state == 0 else { throw MicInputError.audioFormatError }

        var renderCallback = AURenderCallbackStruct(inputProc: { (ptrRefCon, ptrActionFlags, ptrTimeStamp, busNumber, frameCnt, ptrBufferList) -> OSStatus in
            // playCallBack
            guard let ptrBufferList = ptrBufferList,
                ptrBufferList.pointee.mNumberBuffers == 1,
                ptrBufferList.pointee.mBuffers.mNumberChannels <= 1,
                0 < ptrBufferList.pointee.mBuffers.mNumberChannels else { return -1 }
            
            var audioRenderer = ptrRefCon.bindMemory(to: AudioRenderer.self, capacity: MemoryLayout<AudioRenderer>.size).pointee
            audioRenderer.bufferList = ptrBufferList.pointee
            
            let audioBuffer = ptrBufferList.pointee.mBuffers.mData
            let audioBufferSize = ptrBufferList.pointee.mBuffers.mDataByteSize
            
            guard audioBufferSize == ptrBufferList.pointee.mNumberBuffers * 2 * frameCnt else { return -1 }
            
            guard let renderBlock = audioRenderer.renderBlock else { return -1 }
            var outputStatus: OSStatus = 0
            let renderStatus: AVAudioEngineManualRenderingStatus = renderBlock(frameCnt, ptrBufferList, &outputStatus)
            if 10240 < frameCnt || renderStatus != AVAudioEngineManualRenderingStatus.success {
                if 10240 < frameCnt {
                    print ("frameCnt is Exceed")
                }

                var actionFlags = ptrActionFlags.pointee
                actionFlags = AudioUnitRenderActionFlags(rawValue: AudioUnitRenderActionFlags.unitRenderAction_OutputIsSilence.rawValue | actionFlags.rawValue)
                memset(audioBuffer, 0, Int(audioBufferSize))
            }
            
            return 0
         }, inputProcRefCon: UnsafeMutableRawPointer(&audioRenderer))
        state = AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Output, 0, &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard state == 0 else { throw MicInputError.audioFormatError }
        
        var captureCallback = AURenderCallbackStruct(inputProc: { (ptrRefCon, ptrActionFlags, ptrTimeStamp, busNumber, frameCnt, ptrBufferList) -> OSStatus in
            guard frameCnt <= 10240 else { return -1 }
            
            var audioCapturer = ptrRefCon.bindMemory(to: AudioCapturer.self, capacity: MemoryLayout<AudioCapturer>.size).pointee
            guard var bufferList = audioCapturer.bufferList else { return -1 }

            bufferList.mBuffers.mDataByteSize = frameCnt * UInt32(MemoryLayout<UInt16>.size)
            bufferList.mBuffers.mData = nil
            
            var status: OSStatus = 0
            status = AudioUnitRender(audioCapturer.audioUnit!, ptrActionFlags, ptrTimeStamp, 1, frameCnt, UnsafeMutablePointer<AudioBufferList>(&bufferList))
            guard status == 0 else { return -1 }
            
            #if DEBUG
            let audioCapacity = Int(bufferList.mBuffers.mDataByteSize)
            if 0 < audioCapacity,
                let ptrData = bufferList.mBuffers.mData?.bindMemory(to: UInt8.self, capacity: audioCapacity) {
                print("rendered data appended. size: \(audioCapacity)")
                
                let data = Data(bytes: ptrData, count: audioCapacity)
                audioCapturer.renderedData.append(data)
            }

            #endif

//            guard var mixedAudioBufferList = audioCapturer.mixedBufferList,
//                mixedAudioBufferList.mNumberBuffers == bufferList.mNumberBuffers else { return -1 }
//
//            print("buffer cnt: \(bufferList.mNumberBuffers)")
//            for _ in (0..<bufferList.mNumberBuffers) {
//                mixedAudioBufferList.mBuffers.mNumberChannels = bufferList.mBuffers.mNumberChannels
//                mixedAudioBufferList.mBuffers.mDataByteSize = bufferList.mBuffers.mDataByteSize
//            }
            
            var outputStatus: OSStatus = 0
            guard let renderBlock = audioCapturer.renderBlock else { return -1 }
            let result = renderBlock(frameCnt, UnsafeMutablePointer<AudioBufferList>(&bufferList), &outputStatus)
            guard [AVAudioEngineManualRenderingStatus.success, AVAudioEngineManualRenderingStatus.insufficientDataFromInputNode].contains(result) else { return -1 }
            
            // TODO: write!!
                        
            return 0
        }, inputProcRefCon: UnsafeMutableRawPointer(&audioCapturer))
        state = AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Input, 1, &captureCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard state == 0 else { throw MicInputError.audioFormatError }
        
        audioCapturer.audioUnit = audioUnit
    }
    
    public func play() {
        // player
        guard let playAudioFile = playAudioFile else { return }
        
        playFilePlayer.play()
        playFilePlayer.scheduleFile(playAudioFile, at: AVAudioTime(hostTime: 0)) {
            print("played!")
        }
        
        // capturer
        captureEngine.connect(captureEngine.inputNode, to: captureEngine.mainMixerNode, format: audioFormat)
        captureEngine.inputNode.installTap(onBus: 1, bufferSize: 10240, format: audioFormat) { [weak self] (pcmBuffer, audioTime) in
            guard let int16ChannelData = pcmBuffer.int16ChannelData?.pointee else { return }
            self?.audioCapturer.bufferList?.mBuffers.mDataByteSize = pcmBuffer.frameLength * 2
            self?.audioCapturer.bufferList?.mBuffers.mData = UnsafeMutableRawPointer(int16ChannelData)
            
            #if DEBUG
            int16ChannelData.withMemoryRebound(to: UInt8.self, capacity: Int(pcmBuffer.frameLength*2)) { [weak self] (ptrData) -> Void in
                self?.capturedData.append(ptrData, count: Int(pcmBuffer.frameLength*2))
            }
            #endif
        }
        try? captureEngine.start()
    }
    
    public func stop() {
        playFilePlayer.stop()
        
        #if DEBUG
        let capturedFileName = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0].appendingPathComponent("captured.raw")
        let captureEngineInputFileName = FileManager.default.urls(for: .documentDirectory,
                                                                  in: .userDomainMask)[0].appendingPathComponent("captureEngineInput.raw")
        let captureEngineRenderFileName = FileManager.default.urls(for: .documentDirectory,
                                                                  in: .userDomainMask)[0].appendingPathComponent("captureEngineRender.raw")
        do {
            try capturedData.write(to: capturedFileName)
            try audioCapturer.inputData.write(to: captureEngineInputFileName)
            try audioCapturer.renderedData.write(to: captureEngineRenderFileName)
            print("captured data to file :\(capturedFileName), size: \(capturedData.count)")
            print("captureEngineInput data to file :\(captureEngineInputFileName), size: \(audioCapturer.inputData.count)")
            print("captureEngineInput data to file :\(captureEngineRenderFileName), size: \(audioCapturer.renderedData.count)")
            
            capturedData.removeAll()
        } catch {}
        #endif
    }
}
