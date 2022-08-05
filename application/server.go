package main

import (
  "fmt"
  "log"
  "net/http"
  "time"
   "os"
   "runtime"
//   "text/template"
)

func appHandler(w http.ResponseWriter, r *http.Request) {

  fmt.Println(time.Now(), "Hello from my new fresh server")

}

func homeHandler(w http.ResponseWriter, r *http.Request) {
    myOS, myArch := runtime.GOOS, runtime.GOARCH
    inContainer := "inside"
    if _, err := os.Lstat("/.dockerenv"); err != nil && os.IsNotExist(err) {
        inContainer = "outside"
    }
    w.Header().Set("Content-Type", "text/html")
    w.WriteHeader(http.StatusOK)
    _, _ = fmt.Fprintf(w, "Hello, %s!\n", r.UserAgent())
    _, _ = fmt.Fprintf(w, "I'm running on %s/%s.\<\p\>", myOS, myArch)
    _, _ = fmt.Fprintf(w, "I'm running %s of a container.\<\p\>", inContainer)
    _, _ = fmt.Fprintf(w, "I'm running %s version container.\<\p\>",  os.Getenv("BUILD_NUMBER"))
    _, _ = fmt.Fprintf(w, "This is my first Go project. Within ITEA courses .\<\p\>") 
    _, _ = fmt.Fprintf(w, "Sources you can find on my git https://github.com/sergharkov/itea .\<\p\>") 
    _, _ = fmt.Fprintf(w, "\n %s \n", os.Getenv("IMG_PRINT"))
}


func main() {
//  http.HandleFunc("/", appHandler)
  http.HandleFunc("/", homeHandler)

  log.Println("Started, serving on port 8080")
  err := http.ListenAndServe(":8080", nil)

  if err != nil {
    log.Fatal(err.Error())
  }
}
