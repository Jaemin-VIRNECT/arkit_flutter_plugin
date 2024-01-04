import ARKit

func getCenterPosition(_ sceneView: ARSCNView) -> SCNVector3? {
 var floorNode = sceneView.pointOfView?.childNode(withName: "floorNode", recursively: false)
    if(floorNode == nil){
        floorNode = SCNNode(geometry: SCNFloor())
        floorNode!.name = "floorNode"
        floorNode!.isHidden = true
        sceneView.pointOfView?.addChildNode(floorNode!)
        floorNode!.position.z = -0.5
        floorNode!.eulerAngles.x = -.pi / 2
    }
    let screenSize = sceneView.bounds.size
    let touchPoint = CGPoint(x: screenSize.width / 2.0, y: screenSize.height / 2.0)

    guard let lastHit = sceneView.hitTest(touchPoint, options: [
            SCNHitTestOption.rootNode: floorNode!, SCNHitTestOption.ignoreHiddenNodes: false
        ]).first else {
        return nil
    }
    return lastHit.worldCoordinates
}

func getARHitResultsArray(_ sceneView: ARSCNView, atLocation location: CGPoint) -> [[String: Any]] {
  let arHitResults = getARHitResults(sceneView, atLocation: location)
  let results = convertHitResultsToArray(arHitResults)
  return results
}

func getARHitResults(_ sceneView: ARSCNView, atLocation location: CGPoint) -> [ARHitTestResult] {
  var types = ARHitTestResult.ResultType(
    [.featurePoint, .estimatedHorizontalPlane, .existingPlane, .existingPlaneUsingExtent])
  
  if #available(iOS 11.3, *) {
    types.insert(.estimatedVerticalPlane)
    types.insert(.existingPlaneUsingGeometry)
  }
  let results = sceneView.hitTest(location, types: types)
  return results
}

private func convertHitResultsToArray(_ array: [ARHitTestResult]) -> [[String: Any]] {
  return array.map { getDictFromHitResult($0) }
}

private func getDictFromHitResult(_ result: ARHitTestResult) -> [String: Any] {
  var dict = [String: Any](minimumCapacity: 4)
  dict["type"] = result.type.rawValue
  dict["distance"] = result.distance
  dict["localTransform"] = serializeMatrix(result.localTransform)
  dict["worldTransform"] = serializeMatrix(result.worldTransform)
  
  if let anchor = result.anchor {
    dict["anchor"] = serializeAnchor(anchor)
  }
  
  return dict
}
