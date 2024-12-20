import Foundation

struct Payload: Codable {
  let cells: [[Cell]]
  let pieces: [Piece]
  let owner: Player
}

actor ComputerMaster: Computer {
  let owner: Player
  
  init(owner: Player) {
    self.owner = owner
  }
  
  func moveCandidate(board: Board, pieces: [Piece]) async -> Candidate? {
    do {
      let cells = board.cells
      
      let url = URL(string: "https://blokus-computer.tomoki69386.workers.dev/api/computer/master")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
      let payload = Payload(cells: cells, pieces: pieces, owner: owner)
      let encoder = JSONEncoder()
      request.httpBody = try encoder.encode(payload)
      
      let (data, response) = try await URLSession.shared.data(for: request)
      guard
        let httpResponse = response as? HTTPURLResponse,
        (200..<300).contains(httpResponse.statusCode)
      else {
        print("Server returned an error")
        return nil
      }
      
      let decoder = JSONDecoder()
      return try decoder.decode(Candidate.self, from: data)
      
    } catch {
      print("Computer has no pieces left and passes.")
      return nil
    }
  }
}
