import Foundation

// MARK: - Weight Structures

public struct DenseLayerWeights: Codable, Hashable, Sendable {
  public var weights: [Double]
  public var bias: [Double]
  public var inputSize: Int
  public var outputSize: Int

  public static func heInit(inputSize: Int, outputSize: Int, rng: inout SplitMix64) -> DenseLayerWeights {
    let scale = sqrt(2.0 / Double(inputSize))
    let weights = (0..<(outputSize * inputSize)).map { _ in rng.nextGaussian() * scale }
    let bias = Array(repeating: 0.0, count: outputSize)
    return DenseLayerWeights(weights: weights, bias: bias, inputSize: inputSize, outputSize: outputSize)
  }

  public static func zeros(inputSize: Int, outputSize: Int) -> DenseLayerWeights {
    DenseLayerWeights(
      weights: Array(repeating: 0.0, count: outputSize * inputSize),
      bias: Array(repeating: 0.0, count: outputSize),
      inputSize: inputSize,
      outputSize: outputSize
    )
  }
}

public struct Conv2DLayerWeights: Codable, Hashable, Sendable {
  public var filters: [Double]
  public var bias: [Double]
  public var inChannels: Int
  public var outChannels: Int
  public var kernelSize: Int

  public static func heInit(
    inChannels: Int,
    outChannels: Int,
    kernelSize: Int,
    rng: inout SplitMix64
  ) -> Conv2DLayerWeights {
    let fanIn = inChannels * kernelSize * kernelSize
    let scale = sqrt(2.0 / Double(fanIn))
    let count = outChannels * inChannels * kernelSize * kernelSize
    let filters = (0..<count).map { _ in rng.nextGaussian() * scale }
    let bias = Array(repeating: 0.0, count: outChannels)
    return Conv2DLayerWeights(
      filters: filters, bias: bias,
      inChannels: inChannels, outChannels: outChannels, kernelSize: kernelSize
    )
  }
}

public struct MLPWeights: Codable, Hashable, Sendable {
  public var layers: [DenseLayerWeights]
  public var inputSize: Int
}

public struct CNNWeights: Codable, Hashable, Sendable {
  public var convLayers: [Conv2DLayerWeights]
  public var denseLayers: [DenseLayerWeights]
  public var boardSize: Int
  public var inputChannels: Int
}

// MARK: - Forward Operations

public enum NeuralNetOps {
  public static func denseForward(input: [Double], layer: DenseLayerWeights) -> [Double] {
    var output = layer.bias
    for i in 0..<layer.outputSize {
      var sum = output[i]
      let offset = i * layer.inputSize
      for j in 0..<layer.inputSize {
        sum += layer.weights[offset + j] * input[j]
      }
      output[i] = sum
    }
    return output
  }

  public static func relu(_ x: [Double]) -> [Double] {
    x.map { max(0, $0) }
  }

  public static func conv2dForward(
    input: [Double],
    width: Int,
    height: Int,
    layer: Conv2DLayerWeights
  ) -> [Double] {
    let pad = layer.kernelSize / 2
    let spatialSize = height * width
    var output = Array(repeating: 0.0, count: layer.outChannels * spatialSize)

    for co in 0..<layer.outChannels {
      let biasVal = layer.bias[co]
      let outBase = co * spatialSize
      for idx in 0..<spatialSize {
        output[outBase + idx] = biasVal
      }

      for ci in 0..<layer.inChannels {
        let inBase = ci * spatialSize
        for ky in 0..<layer.kernelSize {
          for kx in 0..<layer.kernelSize {
            let filterVal =
              layer.filters[
                ((co * layer.inChannels + ci) * layer.kernelSize + ky) * layer.kernelSize + kx]
            for y in 0..<height {
              let iy = y + ky - pad
              guard iy >= 0, iy < height else { continue }
              for x in 0..<width {
                let ix = x + kx - pad
                guard ix >= 0, ix < width else { continue }
                output[outBase + y * width + x] += filterVal * input[inBase + iy * width + ix]
              }
            }
          }
        }
      }
    }

    return output
  }

  public static func globalAvgPool(
    input: [Double],
    channels: Int,
    width: Int,
    height: Int
  ) -> [Double] {
    let spatialSize = width * height
    let inv = 1.0 / Double(spatialSize)
    var output = Array(repeating: 0.0, count: channels)
    for c in 0..<channels {
      var sum = 0.0
      let offset = c * spatialSize
      for i in 0..<spatialSize {
        sum += input[offset + i]
      }
      output[c] = sum * inv
    }
    return output
  }
}

// MARK: - MLP

public enum MLPInference {
  public static func predict(input: [Double], weights: MLPWeights) -> Double {
    var x = input
    for (i, layer) in weights.layers.enumerated() {
      x = NeuralNetOps.denseForward(input: x, layer: layer)
      if i < weights.layers.count - 1 {
        x = NeuralNetOps.relu(x)
      }
    }
    return max(-1, min(1, x[0]))
  }

  public static func predictRaw(input: [Double], weights: MLPWeights) -> Double {
    var x = input
    for (i, layer) in weights.layers.enumerated() {
      x = NeuralNetOps.denseForward(input: x, layer: layer)
      if i < weights.layers.count - 1 {
        x = NeuralNetOps.relu(x)
      }
    }
    return x[0]
  }
}

public enum MLPTrainer {
  public static func train(
    features: [[Double]],
    targets: [Double],
    hiddenSizes: [Int] = [64, 32],
    epochs: Int = 20,
    learningRate: Double = 0.001,
    batchSize: Int = 256,
    seed: UInt64 = 42,
    progress: ((Int, Double) -> Void)? = nil
  ) -> MLPWeights {
    var rng = SplitMix64(seed: seed)
    let inputSize = features[0].count
    let sizes = [inputSize] + hiddenSizes + [1]
    var layers: [DenseLayerWeights] = []
    for i in 0..<(sizes.count - 1) {
      if i < sizes.count - 2 {
        layers.append(.heInit(inputSize: sizes[i], outputSize: sizes[i + 1], rng: &rng))
      } else {
        layers.append(.zeros(inputSize: sizes[i], outputSize: sizes[i + 1]))
      }
    }

    let n = features.count
    var indices = Array(0..<n)

    for epoch in 0..<epochs {
      for i in stride(from: n - 1, through: 1, by: -1) {
        let j = Int(rng.next() % UInt64(i + 1))
        indices.swapAt(i, j)
      }

      var epochLoss = 0.0
      for batchStart in stride(from: 0, to: n, by: batchSize) {
        let batchEnd = min(batchStart + batchSize, n)
        let currentBatch = batchEnd - batchStart

        var dW = layers.map { Array(repeating: 0.0, count: $0.weights.count) }
        var dB = layers.map { Array(repeating: 0.0, count: $0.bias.count) }

        for b in batchStart..<batchEnd {
          let i = indices[b]
          let (loss, grads) = backprop(input: features[i], target: targets[i], layers: layers)
          epochLoss += loss
          for l in 0..<layers.count {
            for w in 0..<dW[l].count { dW[l][w] += grads[l].0[w] }
            for b in 0..<dB[l].count { dB[l][b] += grads[l].1[b] }
          }
        }

        let scale = learningRate / Double(currentBatch)
        for l in 0..<layers.count {
          for w in 0..<layers[l].weights.count { layers[l].weights[w] -= scale * dW[l][w] }
          for b in 0..<layers[l].bias.count { layers[l].bias[b] -= scale * dB[l][b] }
        }
      }

      let avgLoss = epochLoss / Double(n)
      progress?(epoch + 1, avgLoss)
    }

    return MLPWeights(layers: layers, inputSize: inputSize)
  }

  private static func backprop(
    input: [Double],
    target: Double,
    layers: [DenseLayerWeights]
  ) -> (Double, [(dWeights: [Double], dBias: [Double])]) {
    var activations: [[Double]] = [input]
    var preActivations: [[Double]] = []
    var x = input

    for (i, layer) in layers.enumerated() {
      let z = NeuralNetOps.denseForward(input: x, layer: layer)
      preActivations.append(z)
      x = (i < layers.count - 1) ? NeuralNetOps.relu(z) : z
      activations.append(x)
    }

    let prediction = max(-1, min(1, x[0]))
    let diff = prediction - target
    let loss = diff * diff

    var delta: [Double] = (x[0] > 1 || x[0] < -1) ? [0.0] : [2.0 * diff]
    var gradients: [(dWeights: [Double], dBias: [Double])] = []

    for l in stride(from: layers.count - 1, through: 0, by: -1) {
      let layerInput = activations[l]
      let layer = layers[l]
      var dW = Array(repeating: 0.0, count: layer.weights.count)
      let dB = delta

      for i in 0..<layer.outputSize {
        let offset = i * layer.inputSize
        for j in 0..<layer.inputSize {
          dW[offset + j] = delta[i] * layerInput[j]
        }
      }

      gradients.append((dW, dB))

      if l > 0 {
        var dInput = Array(repeating: 0.0, count: layer.inputSize)
        for i in 0..<layer.outputSize {
          let offset = i * layer.inputSize
          for j in 0..<layer.inputSize {
            dInput[j] += delta[i] * layer.weights[offset + j]
          }
        }
        let preAct = preActivations[l - 1]
        for j in 0..<dInput.count {
          if preAct[j] <= 0 { dInput[j] = 0 }
        }
        delta = dInput
      }
    }

    gradients.reverse()
    return (loss, gradients)
  }
}

// MARK: - CNN

public enum CNNInference {
  public static func predict(boardChannels: [Double], weights: CNNWeights) -> Double {
    var x = boardChannels
    let size = weights.boardSize
    for convLayer in weights.convLayers {
      x = NeuralNetOps.conv2dForward(input: x, width: size, height: size, layer: convLayer)
      x = NeuralNetOps.relu(x)
    }

    let lastChannels = weights.convLayers.last?.outChannels ?? weights.inputChannels
    x = NeuralNetOps.globalAvgPool(input: x, channels: lastChannels, width: size, height: size)

    for (i, denseLayer) in weights.denseLayers.enumerated() {
      x = NeuralNetOps.denseForward(input: x, layer: denseLayer)
      if i < weights.denseLayers.count - 1 {
        x = NeuralNetOps.relu(x)
      }
    }

    return max(-1, min(1, x[0]))
  }
}

public enum CNNTrainer {
  public static func train(
    boards: [[Double]],
    targets: [Double],
    convChannelsList: [Int] = [8, 8],
    denseHidden: [Int] = [32],
    boardSize: Int = 20,
    inputChannels: Int = 4,
    epochs: Int = 10,
    learningRate: Double = 0.001,
    batchSize: Int = 128,
    seed: UInt64 = 42,
    progress: ((Int, Double) -> Void)? = nil
  ) -> CNNWeights {
    var rng = SplitMix64(seed: seed)

    var convLayers: [Conv2DLayerWeights] = []
    var inCh = inputChannels
    for outCh in convChannelsList {
      convLayers.append(.heInit(inChannels: inCh, outChannels: outCh, kernelSize: 3, rng: &rng))
      inCh = outCh
    }

    let pooledSize = convChannelsList.last ?? inputChannels
    var denseLayers: [DenseLayerWeights] = []
    var denseIn = pooledSize
    for h in denseHidden {
      denseLayers.append(.heInit(inputSize: denseIn, outputSize: h, rng: &rng))
      denseIn = h
    }
    denseLayers.append(.zeros(inputSize: denseIn, outputSize: 1))

    let n = boards.count
    var indices = Array(0..<n)

    for epoch in 0..<epochs {
      for i in stride(from: n - 1, through: 1, by: -1) {
        let j = Int(rng.next() % UInt64(i + 1))
        indices.swapAt(i, j)
      }

      var epochLoss = 0.0
      for batchStart in stride(from: 0, to: n, by: batchSize) {
        let batchEnd = min(batchStart + batchSize, n)
        let currentBatch = batchEnd - batchStart

        var convDFilters = convLayers.map { Array(repeating: 0.0, count: $0.filters.count) }
        var convDBias = convLayers.map { Array(repeating: 0.0, count: $0.bias.count) }
        var denseDW = denseLayers.map { Array(repeating: 0.0, count: $0.weights.count) }
        var denseDB = denseLayers.map { Array(repeating: 0.0, count: $0.bias.count) }

        for b in batchStart..<batchEnd {
          let i = indices[b]
          let (loss, cGrads, dGrads) = cnnBackprop(
            input: boards[i],
            target: targets[i],
            convLayers: convLayers,
            denseLayers: denseLayers,
            boardSize: boardSize
          )
          epochLoss += loss
          for l in 0..<convLayers.count {
            for w in 0..<convDFilters[l].count { convDFilters[l][w] += cGrads[l].0[w] }
            for b in 0..<convDBias[l].count { convDBias[l][b] += cGrads[l].1[b] }
          }
          for l in 0..<denseLayers.count {
            for w in 0..<denseDW[l].count { denseDW[l][w] += dGrads[l].0[w] }
            for b in 0..<denseDB[l].count { denseDB[l][b] += dGrads[l].1[b] }
          }
        }

        let scale = learningRate / Double(currentBatch)
        for l in 0..<convLayers.count {
          for w in 0..<convLayers[l].filters.count {
            convLayers[l].filters[w] -= scale * convDFilters[l][w]
          }
          for b in 0..<convLayers[l].bias.count {
            convLayers[l].bias[b] -= scale * convDBias[l][b]
          }
        }
        for l in 0..<denseLayers.count {
          for w in 0..<denseLayers[l].weights.count {
            denseLayers[l].weights[w] -= scale * denseDW[l][w]
          }
          for b in 0..<denseLayers[l].bias.count {
            denseLayers[l].bias[b] -= scale * denseDB[l][b]
          }
        }
      }

      let avgLoss = epochLoss / Double(n)
      progress?(epoch + 1, avgLoss)
    }

    return CNNWeights(
      convLayers: convLayers,
      denseLayers: denseLayers,
      boardSize: boardSize,
      inputChannels: inputChannels
    )
  }

  private static func cnnBackprop(
    input: [Double],
    target: Double,
    convLayers: [Conv2DLayerWeights],
    denseLayers: [DenseLayerWeights],
    boardSize: Int
  ) -> (
    Double,
    [(dFilters: [Double], dBias: [Double])],
    [(dWeights: [Double], dBias: [Double])]
  ) {
    let size = boardSize
    let spatialSize = size * size

    // Forward: conv layers
    var convInputs: [[Double]] = [input]
    var convPreRelu: [[Double]] = []
    var x = input
    for layer in convLayers {
      let z = NeuralNetOps.conv2dForward(input: x, width: size, height: size, layer: layer)
      convPreRelu.append(z)
      x = NeuralNetOps.relu(z)
      convInputs.append(x)
    }

    // Forward: global avg pool
    let lastChannels = convLayers.last?.outChannels ?? convLayers.first?.inChannels ?? 4
    let pooled = NeuralNetOps.globalAvgPool(input: x, channels: lastChannels, width: size, height: size)

    // Forward: dense layers
    var denseActivations: [[Double]] = [pooled]
    var densePreRelu: [[Double]] = []
    var dx = pooled
    for (i, layer) in denseLayers.enumerated() {
      let z = NeuralNetOps.denseForward(input: dx, layer: layer)
      densePreRelu.append(z)
      dx = (i < denseLayers.count - 1) ? NeuralNetOps.relu(z) : z
      denseActivations.append(dx)
    }

    let prediction = max(-1, min(1, dx[0]))
    let diff = prediction - target
    let loss = diff * diff

    // Backward: dense layers
    var delta: [Double] = (dx[0] > 1 || dx[0] < -1) ? [0.0] : [2.0 * diff]
    var denseGrads: [(dWeights: [Double], dBias: [Double])] = []

    for l in stride(from: denseLayers.count - 1, through: 0, by: -1) {
      let layerInput = denseActivations[l]
      let layer = denseLayers[l]
      var dW = Array(repeating: 0.0, count: layer.weights.count)
      let dB = delta

      for i in 0..<layer.outputSize {
        let offset = i * layer.inputSize
        for j in 0..<layer.inputSize {
          dW[offset + j] = delta[i] * layerInput[j]
        }
      }

      denseGrads.append((dW, dB))

      var dInput = Array(repeating: 0.0, count: layer.inputSize)
      for i in 0..<layer.outputSize {
        let offset = i * layer.inputSize
        for j in 0..<layer.inputSize {
          dInput[j] += delta[i] * layer.weights[offset + j]
        }
      }
      if l > 0 {
        let preAct = densePreRelu[l - 1]
        for j in 0..<dInput.count { if preAct[j] <= 0 { dInput[j] = 0 } }
      }
      delta = dInput
    }
    denseGrads.reverse()

    // Backward: global avg pool
    let inv = 1.0 / Double(spatialSize)
    var dConvOut = Array(repeating: 0.0, count: lastChannels * spatialSize)
    for c in 0..<lastChannels {
      let val = delta[c] * inv
      let offset = c * spatialSize
      for i in 0..<spatialSize {
        dConvOut[offset + i] = val
      }
    }

    // Backward: conv layers (with ReLU)
    var convGrads: [(dFilters: [Double], dBias: [Double])] = []
    var dOut = dConvOut

    for l in stride(from: convLayers.count - 1, through: 0, by: -1) {
      let preRelu = convPreRelu[l]
      let layerOutSize = convLayers[l].outChannels * spatialSize
      for i in 0..<layerOutSize {
        if preRelu[i] <= 0 { dOut[i] = 0 }
      }

      let convInput = convInputs[l]
      let layer = convLayers[l]
      let (dF, dB, dI) = conv2dBackward(
        dOutput: dOut, input: convInput, layer: layer, width: size, height: size
      )
      convGrads.append((dF, dB))
      dOut = dI
    }
    convGrads.reverse()

    return (loss, convGrads, denseGrads)
  }

  private static func conv2dBackward(
    dOutput: [Double],
    input: [Double],
    layer: Conv2DLayerWeights,
    width: Int,
    height: Int
  ) -> (dFilters: [Double], dBias: [Double], dInput: [Double]) {
    let pad = layer.kernelSize / 2
    let spatialSize = width * height
    var dFilters = Array(repeating: 0.0, count: layer.filters.count)
    var dBias = Array(repeating: 0.0, count: layer.outChannels)
    var dInput = Array(repeating: 0.0, count: layer.inChannels * spatialSize)

    for co in 0..<layer.outChannels {
      let outBase = co * spatialSize
      var biasGrad = 0.0
      for i in 0..<spatialSize { biasGrad += dOutput[outBase + i] }
      dBias[co] = biasGrad

      for ci in 0..<layer.inChannels {
        let inBase = ci * spatialSize
        for ky in 0..<layer.kernelSize {
          for kx in 0..<layer.kernelSize {
            let fIdx =
              ((co * layer.inChannels + ci) * layer.kernelSize + ky) * layer.kernelSize + kx
            var fGrad = 0.0

            for y in 0..<height {
              let iy = y + ky - pad
              guard iy >= 0, iy < height else { continue }
              for x in 0..<width {
                let ix = x + kx - pad
                guard ix >= 0, ix < width else { continue }
                let dOutVal = dOutput[outBase + y * width + x]
                fGrad += dOutVal * input[inBase + iy * width + ix]
                dInput[inBase + iy * width + ix] += dOutVal * layer.filters[fIdx]
              }
            }
            dFilters[fIdx] = fGrad
          }
        }
      }
    }

    return (dFilters, dBias, dInput)
  }
}

// MARK: - Policy MLP Trainer

public enum PolicyMLPTrainer {
  public struct PolicySample {
    public var moveFeatures: [[Double]]
    public var targetProbs: [Double]

    public init(moveFeatures: [[Double]], targetProbs: [Double]) {
      self.moveFeatures = moveFeatures
      self.targetProbs = targetProbs
    }
  }

  public static func train(
    samples: [PolicySample],
    inputSize: Int = MoveFeatureExtractor.featureCount,
    hiddenSizes: [Int] = [32, 16],
    epochs: Int = 20,
    learningRate: Double = 0.001,
    batchSize: Int = 256,
    seed: UInt64 = 42,
    progress: ((Int, Double) -> Void)? = nil
  ) -> MLPWeights {
    var rng = SplitMix64(seed: seed)
    let sizes = [inputSize] + hiddenSizes + [1]
    var layers: [DenseLayerWeights] = []
    for i in 0..<(sizes.count - 1) {
      if i < sizes.count - 2 {
        layers.append(.heInit(inputSize: sizes[i], outputSize: sizes[i + 1], rng: &rng))
      } else {
        layers.append(.zeros(inputSize: sizes[i], outputSize: sizes[i + 1]))
      }
    }

    let n = samples.count
    guard n > 0 else { return MLPWeights(layers: layers, inputSize: inputSize) }
    var indices = Array(0..<n)

    for epoch in 0..<epochs {
      for i in stride(from: n - 1, through: 1, by: -1) {
        let j = Int(rng.next() % UInt64(i + 1))
        indices.swapAt(i, j)
      }

      var epochLoss = 0.0
      for batchStart in stride(from: 0, to: n, by: batchSize) {
        let batchEnd = min(batchStart + batchSize, n)
        let currentBatch = batchEnd - batchStart

        var dW = layers.map { Array(repeating: 0.0, count: $0.weights.count) }
        var dB = layers.map { Array(repeating: 0.0, count: $0.bias.count) }

        for b in batchStart..<batchEnd {
          let sample = samples[indices[b]]
          let (loss, grads) = policyBackprop(sample: sample, layers: layers)
          epochLoss += loss
          for l in 0..<layers.count {
            for w in 0..<dW[l].count { dW[l][w] += grads[l].0[w] }
            for bi in 0..<dB[l].count { dB[l][bi] += grads[l].1[bi] }
          }
        }

        let scale = learningRate / Double(currentBatch)
        for l in 0..<layers.count {
          for w in 0..<layers[l].weights.count { layers[l].weights[w] -= scale * dW[l][w] }
          for bi in 0..<layers[l].bias.count { layers[l].bias[bi] -= scale * dB[l][bi] }
        }
      }

      let avgLoss = epochLoss / Double(n)
      progress?(epoch + 1, avgLoss)
    }

    return MLPWeights(layers: layers, inputSize: inputSize)
  }

  private static func policyBackprop(
    sample: PolicySample,
    layers: [DenseLayerWeights]
  ) -> (Double, [(dWeights: [Double], dBias: [Double])]) {
    let moveCount = sample.moveFeatures.count
    guard moveCount > 0 else {
      let zeroGrads = layers.map { (Array(repeating: 0.0, count: $0.weights.count), Array(repeating: 0.0, count: $0.bias.count)) }
      return (0, zeroGrads)
    }

    // Forward pass: compute logits and cache activations for each move
    var allActivations: [[[Double]]] = []
    var allPreActivations: [[[Double]]] = []
    var logits: [Double] = []
    logits.reserveCapacity(moveCount)

    for m in 0..<moveCount {
      var activations: [[Double]] = [sample.moveFeatures[m]]
      var preActs: [[Double]] = []
      var x = sample.moveFeatures[m]
      for (i, layer) in layers.enumerated() {
        let z = NeuralNetOps.denseForward(input: x, layer: layer)
        preActs.append(z)
        x = (i < layers.count - 1) ? NeuralNetOps.relu(z) : z
        activations.append(x)
      }
      logits.append(x[0])
      allActivations.append(activations)
      allPreActivations.append(preActs)
    }

    // Softmax
    let maxLogit = logits.max() ?? 0
    let exps = logits.map { exp($0 - maxLogit) }
    let sumExp = max(1e-9, exps.reduce(0, +))
    let softmaxProbs = exps.map { $0 / sumExp }

    // Cross-entropy loss
    var loss = 0.0
    for m in 0..<moveCount {
      if sample.targetProbs[m] > 1e-9 {
        loss -= sample.targetProbs[m] * log(max(1e-9, softmaxProbs[m]))
      }
    }

    // Backward: accumulate gradients across all moves
    var totalGrads: [(dWeights: [Double], dBias: [Double])] = layers.map {
      (Array(repeating: 0.0, count: $0.weights.count), Array(repeating: 0.0, count: $0.bias.count))
    }

    for m in 0..<moveCount {
      let dLogit = softmaxProbs[m] - sample.targetProbs[m]
      var delta: [Double] = [dLogit]
      let activations = allActivations[m]
      let preActs = allPreActivations[m]

      for l in stride(from: layers.count - 1, through: 0, by: -1) {
        let layerInput = activations[l]
        let layer = layers[l]

        for i in 0..<layer.outputSize {
          let offset = i * layer.inputSize
          for j in 0..<layer.inputSize {
            totalGrads[l].0[offset + j] += delta[i] * layerInput[j]
          }
          totalGrads[l].1[i] += delta[i]
        }

        if l > 0 {
          var dInput = Array(repeating: 0.0, count: layer.inputSize)
          for i in 0..<layer.outputSize {
            let offset = i * layer.inputSize
            for j in 0..<layer.inputSize {
              dInput[j] += delta[i] * layer.weights[offset + j]
            }
          }
          let preAct = preActs[l - 1]
          for j in 0..<dInput.count {
            if preAct[j] <= 0 { dInput[j] = 0 }
          }
          delta = dInput
        }
      }
    }

    return (loss, totalGrads)
  }
}
