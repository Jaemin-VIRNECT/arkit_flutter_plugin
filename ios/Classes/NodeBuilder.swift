import ARKit
import GLTFSceneKit
import SCNLine

func createNode(_ geometry: SCNGeometry?, fromDict dict: [String: Any], forDevice device: MTLDevice?, channel: FlutterMethodChannel) -> SCNNode {
  let dartType = dict["dartType"] as! String
  let node: SCNNode
  
  switch dartType {
  case "ARKitLineNode":
    node = createSCNLineNode(dict)
  case "ARKitReferenceNode":
    node = createReferenceNode(dict)
  case "ARKitGltfNode":
    node = createGltfNode(dict, channel: channel)
  default:
    node = SCNNode(geometry: geometry)
  }
  
  updateNode(node, fromDict: dict, forDevice: device)
  return node
}

func updateNode(_ node: SCNNode, fromDict dict: [String: Any], forDevice device: MTLDevice?) {
  if let transform = dict["transform"] as? [NSNumber] {
    node.transform = deserializeMatrix4(transform)
  }
  
  if let name = dict["name"] as? String {
    node.name = name
  }
  
  if let physicsBody = dict["physicsBody"] as? [String: Any] {
    node.physicsBody = createPhysicsBody(physicsBody, forDevice: device)
  }
  
  if let light = dict["light"] as? [String: Any] {
    node.light = createLight(light)
  }
  
  if let renderingOrder = dict["renderingOrder"] as? Int {
    node.renderingOrder = renderingOrder
  }
  
  if let isHidden = dict["isHidden"] as? Bool {
    node.isHidden = isHidden
  }
}

fileprivate func createSCNLineNode(_ dict: Dictionary<String, Any>) -> SCNNode {

    let radius = dict["radius"] as! Double
    let edges = dict["edges"] as! Int
    let maxTurning = dict["maxTurning"] as! Int
    let node = SCNLineNode(with: [], radius: Float(radius), edges: edges, maxTurning: maxTurning)

    if let materials = dict["materials"] as? [[String: Any]] {
        node.lineMaterials = parseMaterials(materials)
    }else{
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(
            displayP3Red: CGFloat.random(in: 0...1),
            green: CGFloat.random(in: 0...1),
            blue: CGFloat.random(in: 0...1),
            alpha: 1
        )
        material.isDoubleSided = true
        node.lineMaterials = [material]
    }
    return node
}

func updateLineNode(_ sceneView: ARSCNView, _ node: SCNLineNode, fromDict dict: [String: Any], channel: FlutterMethodChannel) {
    guard let x = dict["x"] as? Double, let y = dict["y"] as? Double else {
        logPluginError("Invalid touch coordinates", toChannel: channel)
        return
    }
    let touchPoint = CGPoint(x: x, y: y)
    if(node.points.isEmpty){
        var types = ARHitTestResult.ResultType([.featurePoint])
        let hitResults = sceneView.hitTest(touchPoint, types: types)
        guard let hitResult = hitResults.first else {
            logPluginError("No hit result found", toChannel: channel)
            return
        }
        let worldTransform = hitResult.worldTransform
        let worldCoordinates = SCNVector3(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
        node.add(point: SCNVector3(worldCoordinates.x, worldCoordinates.y, worldCoordinates.z))
    } else {
        guard let initialPoint = node.points.first else { return }
        guard let lastPoint = node.points.last else { return }
        let projectedPoint = sceneView.projectPoint(initialPoint)
        let unprojectedPoint = sceneView.unprojectPoint(SCNVector3(Float(touchPoint.x), Float(touchPoint.y), projectedPoint.z))
        let diff = SCNVector3(unprojectedPoint.x - lastPoint.x, unprojectedPoint.y - lastPoint.y, unprojectedPoint.z - lastPoint.z)
        let distance = sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)
        if distance > 0.012 {
            node.add(point: unprojectedPoint)
        }
    }
}

private func createGltfNode(_ dict: [String: Any], channel: FlutterMethodChannel) -> SCNNode {
  let url = dict["url"] as! String
  let urlLowercased = url.lowercased()
  let node = SCNNode()
  
  if urlLowercased.hasSuffix(".gltf") || urlLowercased.hasSuffix(".glb") {
    let assetTypeIndex = dict["assetType"] as? Int
    let isFromFlutterAssets = assetTypeIndex == 0
    let sceneSource: GLTFSceneSource
    
    do {
      if isFromFlutterAssets {
        // load model from Flutter assets
        let modelPath = FlutterDartProject.lookupKey(forAsset: url)
        sceneSource = try GLTFSceneSource(named: modelPath)
      } else {
        // load model from the Documents folder
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let modelPath = documentsDirectory.appendingPathComponent(url).path
        sceneSource = try GLTFSceneSource(path: modelPath)
      }
      let scene = try sceneSource.scene()
      
      let minX = scene.rootNode.boundingBox.min.x
      let maxX = scene.rootNode.boundingBox.max.x
        
      let scaleValue = 0.15 / abs(minX - maxX)

      scene.rootNode.scale = SCNVector3(scaleValue, scaleValue, scaleValue)

      for child in scene.rootNode.childNodes {
        node.addChildNode(child.flattenedClone())
      }

      if let name = dict["name"] as? String {
        node.name = name
      }
//       if let transform = dict["transform"] as? [NSNumber] {
//         node.transform = deserializeMatrix4(transform)
//       }
    } catch {
      logPluginError("Failed to load file: \(error.localizedDescription)", toChannel: channel)
    }
  } else {
    logPluginError("Only .gltf or .glb files are supported.", toChannel: channel)
  }
  return node
}

private func createReferenceNode(_ dict: [String: Any]) -> SCNReferenceNode {
  let url = dict["url"] as! String
  let referenceUrl: URL
  if let bundleURL = Bundle.main.url(forResource: url, withExtension: nil) {
    referenceUrl = bundleURL
  } else {
    referenceUrl = URL(fileURLWithPath: url)
  }
  let node = SCNReferenceNode(url: referenceUrl)
  node?.load()
  return node!
}

private func createPhysicsBody(_ dict: [String: Any], forDevice device: MTLDevice?) -> SCNPhysicsBody {
  var shape: SCNPhysicsShape?
  if let shapeDict = dict["shape"] as? [String: Any],
     let shapeGeometry = shapeDict["geometry"] as? [String: Any]
  {
    let geometry = createGeometry(shapeGeometry, withDevice: device)
    shape = SCNPhysicsShape(geometry: geometry!, options: nil)
  }
  let type = dict["type"] as! Int
  let bodyType = SCNPhysicsBodyType(rawValue: type)
  let physicsBody = SCNPhysicsBody(type: bodyType!, shape: shape)
  if let categoryBitMack = dict["categoryBitMask"] as? Int {
    physicsBody.categoryBitMask = categoryBitMack
  }
  return physicsBody
}

private func createLight(_ dict: [String: Any]) -> SCNLight {
  let light = SCNLight()
  if let type = dict["type"] as? Int {
    switch type {
    case 0:
      light.type = .ambient
    case 1:
      light.type = .omni
    case 2:
      light.type = .directional
    case 3:
      light.type = .spot
    case 4:
      light.type = .IES
    case 5:
      light.type = .probe
    case 6:
      if #available(iOS 13.0, *) {
        light.type = .area
      } else {
        // error
        light.type = .omni
      }
    default:
      light.type = .omni
    }
  } else {
    light.type = .omni
  }
  if let temperature = dict["temperature"] as? Double {
    light.temperature = CGFloat(temperature)
  }
  if let intensity = dict["intensity"] as? Double {
    light.intensity = CGFloat(intensity)
  }
  if let spotInnerAngle = dict["spotInnerAngle"] as? Double {
    light.spotInnerAngle = CGFloat(spotInnerAngle)
  }
  if let spotOuterAngle = dict["spotOuterAngle"] as? Double {
    light.spotOuterAngle = CGFloat(spotOuterAngle)
  }
  if let color = dict["color"] as? Int {
    light.color = UIColor(rgb: UInt(color))
  }
  return light
}
