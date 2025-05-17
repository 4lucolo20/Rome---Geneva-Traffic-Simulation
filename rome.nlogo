extensions [gis csv]

breed [nodes node]
breed [searchers searcher]
breed [cars car]
breed [pedestrians pedestrian]
breed [bikers biker]

cars-own [car-path current-node waiting-time car-distance-traveled switched?]
pedestrians-own [
  ped-path
  current-node
  use-public-transport?
  waiting-time
  ped-distance-traveled
]
bikers-own [biker-path current-node waiting-time biker-distance-traveled]

links-own [
  link-maxspeed  ;; in km/h
  link-real-length
]

searchers-own [
  memory
  cost
  total-expected-cost
  localization
  active?
]

nodes-own [
  myneighbors
  test
  network-type
  home-node?
  destination-node?
  public-transport-stop?
  residential-street?
  node-type
  is-congested?
]


globals [
  pic-roads
  pthk
  basemap
  pic-walk
  minx
  miny
  public-transport-routes
  famous-destinations
  car-total-time
  pedestrian-total-time
  biker-total-time
  rush-hour-mode
  congested-nodes
  switched-cars
]


to load-basemap
  ifelse (file-exists? "/Users/luigicolonna/Downloads/rome map4.png") [
    set basemap "/Users/luigicolonna/Downloads/rome map4.png"
    import-pcolors basemap
    resize-world 0 649 0 564  ;; Match the basemap dimensions
    set-patch-size 1
  ] [
    user-message "Basemap image not found! Please check the file path."
  ]
end

to load-public-transport
  set public-transport-routes []

  ifelse file-exists? "/Users/luigicolonna/romastops.csv" [
    let csv-data csv:from-file "/Users/luigicolonna/romastops.csv"
    set csv-data but-first csv-data  ;; skip header

    foreach csv-data [
      row ->
      let line item 2 row
      let lat-str item 3 row
      let lon-str item 4 row

      ;; Make sure values are not empty and look like numbers
      if (lat-str != "") and (lon-str != "") and (is-number? lat-str) and (is-number? lon-str) [
        let lat read-from-string lat-str
        let lon read-from-string lon-str
        set public-transport-routes lput (list line lat lon) public-transport-routes
      ]
    ]
  ] [
    user-message "Public transport CSV not found!"
  ]
end



to assign-home-and-destination-nodes
  ;; Reset previous markings
  ask nodes [
    set home-node? false
    set destination-node? false
    set node-type ""
  ]

  ;; Assign home nodes
  ask n-of 50 nodes with [residential-street?] [
    set home-node? true
    set node-type "home"
  ]

  ;; Assign famous destinations
  foreach famous-destinations [
    destination ->
    let lat item 0 destination
    let lon item 1 destination
    let dest-type item 2 destination

    let nearest-node min-one-of nodes [
      distancexy lon lat
    ]

    if nearest-node != nobody [
      ask nearest-node [
        set destination-node? true
        set node-type dest-type
      ]
    ]
  ]
end


to assign-public-transport-stops
  foreach public-transport-routes [
    stop-info ->
    let stop-lat item 1 stop-info
    let stop-lon item 2 stop-info

    let nearest-node min-one-of nodes [
      distancexy stop-lon stop-lat
    ]

    if nearest-node != nobody [
      ask nearest-node [ set public-transport-stop? true ]
    ]
  ]
end


to mark-special-nodes
  ;; Set home nodes
  ask nodes with [home-node?] [
    set shape "house"
    set color blue
    set size 6
  ]

  ;; Set public transport stops
  ask nodes with [public-transport-stop?] [
    set shape "flag"
    set color red
    set size 6
  ]

  ;; Set shopping destinations
  ask nodes with [node-type = "shopping"] [
    set shape "star"
    set color orange
    set size 6
  ]

  ;; Set office/university destinations
  ask nodes with [node-type = "office"] [
    set shape "triangle"
    set color cyan
    set size 6
  ]

  ;; Set gym destinations
  ask nodes with [node-type = "gym" or node-type = "leisure"] [
    set shape "leaf"
    set color green
    set size 6
  ]
end



to setup
  clear-all
  reset-ticks
  set car-total-time 0
  set pedestrian-total-time 0
  set biker-total-time 0

  load-basemap

  ifelse (file-exists? "/Users/luigicolonna/rome_drive.shp") [
    set pic-roads gis:load-dataset "/Users/luigicolonna/rome_drive.shp"
    gis:set-world-envelope gis:envelope-of pic-roads
    import-pcolors basemap
    create-nodes-and-links
  ] [
    user-message "Shapefile not found! Please check the file path."
  ]

  ifelse (file-exists? "/Users/luigicolonna/rome_walk.shp") [
    set pic-walk gis:load-dataset "/Users/luigicolonna/rome_walk.shp"
    create-walk-nodes-and-links
  ] [
    user-message "Walking shapefile not found!"
  ]

  load-public-transport
  assign-public-transport-stops

  ;; Initialize famous destinations list
  set famous-destinations [
  ;; Tourist Attractions
  [41.890251 12.492373 "tourism"]   ;; Colosseum
  [41.898609 12.476873 "tourism"]   ;; Pantheon
  [41.900932 12.483313 "tourism"]   ;; Trevi Fountain
  [41.902168 12.453937 "tourism"]   ;; St. Peter's Basilica
  [41.905991 12.482775 "tourism"]   ;; Spanish Steps
  [41.911015 12.476190 "tourism"]   ;; Piazza del Popolo
  [41.8947 12.4818 "tourism"]       ;; Campo de' Fiori
  [41.8931 12.4828 "tourism"]       ;; Piazza Venezia
  [41.8894 12.4922 "tourism"]       ;; Palatine Hill
  [41.9029 12.4534 "tourism"]       ;; Vatican Museums
  [41.8902 12.4922 "tourism"]       ;; Arch of Constantine
  [41.8905 12.4922 "tourism"]       ;; Basilica di San Clemente
  [41.8931 12.4828 "tourism"]       ;; Capitoline Museums
  [41.8986 12.4768 "tourism"]       ;; Piazza della Rotonda
  [41.9009 12.4833 "tourism"]       ;; Via del Corso
  [41.9022 12.4539 "tourism"]       ;; Castel Sant'Angelo
  [41.8986 12.4768 "tourism"]       ;; Largo di Torre Argentina
  [41.9029 12.4534 "tourism"]       ;; Sistine Chapel
  [41.9065 12.4823 "tourism"]       ;; Piazza di Spagna
  [41.8986 12.4748 "tourism"]       ;; Piazza Navona

  ;; Parks
  [41.91417 12.49222 "leisure"]     ;; Villa Borghese
  [41.932039 12.501497 "leisure"]   ;; Villa Ada
  [41.885288 12.441474 "leisure"]   ;; Villa Doria Pamphili
  [41.8470 12.5620 "leisure"]       ;; Parco degli Acquedotti
  [41.8694 12.5153 "leisure"]       ;; Parco della Caffarella
  [41.8880 12.4547 "leisure"]       ;; Orange Garden (Giardino degli Aranci)
  [41.9186 12.5113 "leisure"]       ;; Villa Torlonia
  [41.8833 12.4922 "leisure"]       ;; Villa Celimontana
  [41.9311 12.4667 "leisure"]       ;; Villa Glori
  [41.8880 12.4547 "leisure"]       ;; Villa Sciarra

  ;; Offices
  [41.9060 12.4892 "office"]        ;; Deloitte - Via Vittorio Veneto 89
  [41.914455 12.49539 "office"]     ;; EY - Via Po 32
  [41.8731 12.4861 "office"]        ;; PwC - Largo Angelo Fochetti 29
  [41.9020 12.4960 "office"]        ;; KPMG - Via Curtatone 3
  [41.8600 12.4770 "office"]        ;; Accenture - Via Ostiense 92
  [41.9020 12.4960 "office"]        ;; McKinsey - Via Nazionale 54
  [41.9060 12.4892 "office"]        ;; BCG - Via Abruzzi 2/4
  [41.9060 12.4892 "office"]        ;; Bain & Company - Via di San Basilio 72
  [41.8460 12.4560 "office"]        ;; IBM - Via Luigi Stipa 150
  [41.8300 12.4600 "office"]        ;; Oracle - Via Amsterdam 147

  ;; Sports Venues
  [41.9339 12.4544 "leisure"]       ;; Stadio Olimpico
  [41.9295 12.4547 "leisure"]       ;; Stadio Flaminio
  [41.9270 12.4560 "leisure"]       ;; Foro Italico
  [41.8221 12.4578 "gym"] ;; Virgin Active Roma EUR – Via Cina 91
  [41.9295 12.5093 "gym"] ;; Corallo 2 Fitness Club – Via Scirè 31
  [41.9102 12.4663 "gym"] ;; Dabliu Prati – Viale Giulio Cesare 43
  [41.9272 12.4880 "gym"] ;; Dabliu Parioli – Viale Romania 22
  [41.8739 12.4962 "gym"] ;; Dabliu Colosseo – Via Capo d’Africa 5
]

  assign-home-and-destination-nodes
  mark-special-nodes

  setup-cars
  setup-pedestrians
  setup-bikers
  export-world "/Users/luigicolonna/rome_simulation.nlogo"

end


to create-nodes-and-links
  ask nodes [
    set residential-street? false
    set home-node? false
    set destination-node? false
    set public-transport-stop? false
    set node-type ""
  ]

  foreach gis:feature-list-of pic-roads [
    road ->
    let road-speed 50  ;; default speed if no data

    ;; Try to read the maxspeed_c attribute
    if gis:property-value road "maxspeed_c" != nobody [
      set road-speed gis:property-value road "maxspeed_c"
    ]

    foreach gis:vertex-lists-of road [
      vertex-list ->
      let previous-node-pt nobody
      foreach vertex-list [
        vertex ->
        let location gis:location-of vertex
        if not empty? location [
          let raw-x (item 0 location)
          let raw-y (item 1 location)

          create-nodes 1 [
            set myneighbors []
            set xcor raw-x
            set ycor raw-y
            set size 0.2
            set shape "circle"
            set color brown
            set network-type "road"
            set residential-street? false
            set home-node? false
            set destination-node? false
            set public-transport-stop? false
            set node-type ""

            ;; Check if the road type indicates a residential street
            let highway-tag gis:property-value road "highway"
            if (highway-tag != nobody) [
              if (member? "residential" (list highway-tag)) or (member? "living_street" (list highway-tag)) [
                set residential-street? true
              ]
            ]

            if previous-node-pt != nobody [
              create-link-with previous-node-pt [
                set link-maxspeed road-speed
                if gis:property-value road "length_met" != nobody [
                  set link-real-length gis:property-value road "length_met"
                ]
                if link-real-length = nobody [
                  set link-real-length 50 ;; fallback if missing
                ]
              ]
            ]
            set previous-node-pt self
          ]
        ]
      ]
    ]
  ]

  delete-duplicates
  ask nodes [set myneighbors link-neighbors]
  delete-not-connected
  ask links [set thickness 0.1 set color orange]
end



to delete-duplicates
  ask nodes [
    if count nodes-here > 1 [
      ask other nodes-here [
        ask myself [
          create-links-with other [link-neighbors] of myself
        ]
        die
      ]
    ]
  ]
end

to tag-congested-nodes
  ;; Make sure all nodes start clean
  ask nodes [ set is-congested? false ]

  let congested-coords [
  [41.9027835 12.4963655]  ;; Roma Termini
  [41.8902102 12.4922309]  ;; Colosseum
  [41.8890565 12.4825193]  ;; Piazza Venezia
  [41.9009325 12.4833135]  ;; Trevi Fountain
  [41.8954656 12.4823243]  ;; Largo di Torre Argentina
  [41.9132404 12.4869177]  ;; Via Veneto
  [41.9109741 12.4768729]  ;; Piazza del Popolo
  [41.9060322 12.4824301]  ;; Piazza di Spagna
  [41.9257852 12.4579474]  ;; Foro Italico (Stadio Olimpico area)
  [41.8731278 12.4881825]  ;; Piramide
  [41.8766848 12.5009071]  ;; Testaccio
  [41.8812212 12.4861833]  ;; Circo Massimo
  [41.8986111 12.4547369]  ;; Vatican / Castel Sant'Angelo
  [41.9186136 12.5107668]  ;; Piazza Bologna
  [41.9295907 12.5317546]  ;; Tiburtina
  [41.9320391 12.5014966]  ;; Villa Ada - nearby congestion
  [41.8578703 12.5325065]  ;; Cinecittà / Quadraro
  [41.8508618 12.4650181]  ;; EUR (EUR Palasport / Fermi / Marconi)
  [41.8462024 12.4765058]  ;; Via Cristoforo Colombo / Laurentina
  [41.8390083 12.5306345]  ;; Tuscolana/Cinecittà East
]

  foreach congested-coords [
    loc ->
    let lat item 0 loc
    let lon item 1 loc
    let center-node min-one-of nodes [distancexy lon lat]
    ask nodes with [distancexy ([xcor] of center-node) ([ycor] of center-node) < 0.05] [
      set is-congested? true
      set color red
    ]
  ]

  set congested-nodes nodes with [is-congested? = true]
end



to create-walk-nodes-and-links
  foreach gis:feature-list-of pic-walk [
    segment ->
    foreach gis:vertex-lists-of segment [
      vertex-list ->
      let previous-node-pt nobody
      foreach vertex-list [
        vertex ->
        let location gis:location-of vertex
        if not empty? location [
          let raw-x (item 0 location)
          let raw-y (item 1 location)

          let nearby-node one-of nodes with [distancexy raw-x raw-y < 0.001]

          ifelse (nearby-node != nobody) [
            ask nearby-node [ set network-type "shared" ]
            if previous-node-pt != nobody [
              create-link-between-nodes nearby-node previous-node-pt
            ]
            set previous-node-pt nearby-node
          ] [
            create-nodes 1 [
              set myneighbors []
              set xcor raw-x
              set ycor raw-y
              set size 0.2
              set shape "circle"
              set color green
              set network-type "walk"
              set residential-street? false
              set home-node? false
              set destination-node? false
              set public-transport-stop? false
              set node-type ""

              if previous-node-pt != nobody [
                create-link-with previous-node-pt [
                  if gis:property-value segment "length_met" != nobody [
                    set link-real-length gis:property-value segment "length_met"
                  ]
                  if link-real-length = nobody [
                    set link-real-length 30 ;; assume small segments
                  ]
                ]
              ]
              set previous-node-pt self
            ]
          ]
        ]
      ]
    ]
  ]

  delete-duplicates
  ask nodes [set myneighbors link-neighbors]
end


to create-link-between-nodes [node1 node2]
  if node1 != node2 [
    ask node1 [
      if not link-neighbor? node2 [
        create-link-with node2
      ]
    ]
  ]
end



to delete-not-connected
  ask nodes [set test 0]
  ask one-of nodes [set test 1]
  repeat 500 [
    ask nodes with [test = 1] [
      ask myneighbors [
        set test 1
      ]
    ]
  ]

  ask nodes with [test = 0] [die]
end

to setup-cars
  create-cars 20 [
    set color blue
    set size 12
    set shape "car"
    set car-distance-traveled 0
    set switched? false
    let start-node one-of nodes
    set current-node [who] of start-node
    move-to start-node

    ;; Assign a goal node and path
    assign-goal-and-path
  ]
end

to setup-pedestrians
  create-pedestrians 20 [
    set color red
    set size 12
    set shape "person"
    set ped-distance-traveled 0
    let start-node one-of nodes with [network-type != "road"]
    set current-node [who] of start-node
    move-to start-node

    ;; 50% chance to use public transport
    ifelse (random-float 1.0 < 0.5) [
      set use-public-transport? true
    ] [
      set use-public-transport? false
    ]

    assign-ped-path
  ]
end

to setup-bikers
  create-bikers 20 [
    set color green
    set size 12
    set shape "wheel"
    set biker-distance-traveled 0
    let start-node one-of nodes with [network-type != "road"]
    set current-node [who] of start-node
    move-to start-node
    assign-biker-path
  ]
end


to assign-goal-and-path  ;; Helper procedure for cars
  let start-node turtle current-node
  let goal-node one-of nodes with [self != start-node and distance start-node > max-pxcor * 0.5]
  ifelse (goal-node != nobody) [
    set car-path (A* start-node goal-node)
  ] [
    set color gray  ;; Deactivate the car if no goal is found
    set car-path []
  ]
end

to assign-ped-path
  let start-node turtle current-node
  let goal-node one-of nodes with [self != start-node and network-type != "road"]
  ifelse (goal-node != nobody) [
    set ped-path (A* start-node goal-node)
  ] [
    set ped-path []
  ]
end

to assign-biker-path
  let start-node turtle current-node
  let goal-node one-of nodes with [self != start-node and network-type != "road"]
  ifelse (goal-node != nobody) [
    set biker-path (A* start-node goal-node)
  ] [
    set biker-path []
  ]
end

to decide-switch-if-congested
  let path-nodes map [n -> turtle n] car-path
  if any? path-nodes with [member? self congested-nodes] [
    if allow-mode-switch [
      ;; 90% switch to walking, 10% to biking
      ifelse random-float 1.0 < 0.9 [
        hatch-pedestrians 1 [
          set shape "person"
          set color red
          set size 12
          set ped-distance-traveled car-distance-traveled
          set current-node [current-node] of myself
          move-to myself
          assign-ped-path
        ]
      ] [
        hatch-bikers 1 [
          set shape "wheel"
          set color green
          set size 12
          set biker-distance-traveled car-distance-traveled
          set current-node [current-node] of myself
          move-to myself
          assign-biker-path
        ]
      ]
      set switched? true
      set switched-cars switched-cars + 1
      die
    ]
  ]
end


to morning-rush-hour
  set rush-hour-mode "morning"
  set switched-cars 0
  tag-congested-nodes
  if allow-mode-switch [
    ask cars [ decide-switch-if-congested ]
  ]
end

to evening-rush-hour
  set rush-hour-mode "evening"
  set switched-cars 0
  tag-congested-nodes
  if allow-mode-switch [
    ask cars [ decide-switch-if-congested ]
  ]
end


to move-agent [path agent-type]
  if not empty? path [
    let next-node-who item 0 path
    let next-node turtle next-node-who
    let current-pos turtle current-node

    ;; Define the connecting-link early
    let connecting-link one-of (link-set my-links [links] of next-node)

    ;; Default movement
    let move-speed 0.1  ;; default pedestrian walking speed

    if agent-type = "car" [
      if connecting-link != nobody [
        let road-speed [link-maxspeed] of connecting-link
        if rush-hour-mode = "morning" [
          set move-speed (road-speed / 50) * 0.34
        ]
        if rush-hour-mode = "evening" [
          set move-speed (road-speed / 50) * 0.32
        ]
        if rush-hour-mode != "morning" and rush-hour-mode != "evening" [
          set move-speed (road-speed / 50) * 0.8
        ]
      ]
    ]

    if agent-type = "ped" [
      if use-public-transport? [
        ;; Public transport pedestrian: move faster like cars
        if connecting-link != nobody [
          let road-speed [link-maxspeed] of connecting-link
          set move-speed (road-speed / 50) * 0.8
        ]
      ]
      ;; else keep default 0.2
    ]

    if agent-type = "biker" [
      set move-speed 0.35  ;; biking speed
    ]

    face next-node
    fd move-speed

    if distance next-node <= 0.5 [
      move-to next-node
      ;; Now connecting-link is always defined
      if agent-type = "car" [
        if connecting-link != nobody [
          set car-distance-traveled car-distance-traveled + [link-real-length] of connecting-link
        ]
      ]
      if agent-type = "ped" [
        if connecting-link != nobody [
          set ped-distance-traveled ped-distance-traveled + [link-real-length] of connecting-link
        ]
      ]
      if agent-type = "biker" [
        if connecting-link != nobody [
          set biker-distance-traveled biker-distance-traveled + [link-real-length] of connecting-link
        ]
      ]

      set current-node next-node-who
      if agent-type = "car" [set car-path but-first car-path]
      if agent-type = "ped" [set ped-path but-first ped-path]
      if agent-type = "biker" [set biker-path but-first biker-path]

      if empty? path [
        if agent-type = "car" [assign-goal-and-path]
        if agent-type = "ped" [assign-ped-path]
        if agent-type = "biker" [assign-biker-path]
      ]
    ]
  ]
end



to move-daytrip-agent [path agent-type]
  ifelse waiting-time > 0 [
    ;; Still waiting at scenic location
    set waiting-time waiting-time - 1
  ] [
    if not empty? path [
      let next-node-who item 0 path
      let next-node turtle next-node-who
      let current-pos turtle current-node

      ;; Define connecting-link early
      let connecting-link one-of (link-set my-links [links] of next-node)

      ;; Default movement
      let move-speed 0.1  ;; pedestrian default

      if agent-type = "car" [
        if connecting-link != nobody [
          let road-speed [link-maxspeed] of connecting-link
          set move-speed (road-speed / 50) * 0.6  ;; Slightly slower for daytrips
        ]
      ]

      if agent-type = "ped" [
        if use-public-transport? [
          if connecting-link != nobody [
            let road-speed [link-maxspeed] of connecting-link
            set move-speed (road-speed / 50) * 0.6
          ]
        ]
      ]

      if agent-type = "biker" [
        set move-speed 0.3  ;; slightly slower biking for daytrip
      ]

      face next-node
      fd move-speed

      if distance next-node <= 0.5 [
        move-to next-node

        ;; Add distance traveled
        if agent-type = "car" [
          if connecting-link != nobody [
            set car-distance-traveled car-distance-traveled + [link-real-length] of connecting-link
          ]
        ]
        if agent-type = "ped" [
          if connecting-link != nobody [
            set ped-distance-traveled ped-distance-traveled + [link-real-length] of connecting-link
          ]
        ]
        if agent-type = "biker" [
          if connecting-link != nobody [
            set biker-distance-traveled biker-distance-traveled + [link-real-length] of connecting-link
          ]
        ]

        set current-node next-node-who
        if agent-type = "car" [ set car-path but-first car-path ]
        if agent-type = "ped" [ set ped-path but-first ped-path ]
        if agent-type = "biker" [ set biker-path but-first biker-path ]

        ;; 🚩 Arrived at destination
        if [node-type] of next-node != "" [
          set waiting-time 10 + random 20 ;; pause at destination
        ]

        if empty? path [
          if agent-type = "car" [ assign-goal-and-path ]
          if agent-type = "ped" [ assign-ped-path ]
          if agent-type = "biker" [ assign-biker-path ]
        ]
      ]
    ]
  ]
end





to go
  ask cars [
    move-agent car-path "car"
  ]
  ask pedestrians [
    move-agent ped-path "ped"
  ]
  ask bikers [
    move-agent biker-path "biker"
  ]

  ;; Keep links and nodes updated visually
  ask links [set thickness 0.1 set color gray]
  ask nodes [
    if network-type = "walk" [set color green]
    if network-type = "shared" [set color yellow]
  ]
  mark-special-nodes

  tick
end


to go-daytrip
   mark-special-nodes
  ask cars [
    move-daytrip-agent car-path "car"
  ]
  ask pedestrians [
    move-daytrip-agent ped-path "ped"
  ]
  ask bikers [
    move-daytrip-agent biker-path "biker"
  ]

  tick

  ;; Track total time
  set car-total-time car-total-time + count cars
  set pedestrian-total-time pedestrian-total-time + count pedestrians
  set biker-total-time biker-total-time + count bikers

  ;; Update visual
  ask links [set thickness 0.1 set color gray]
  ask nodes [
    if network-type = "walk" [set color green]
    if network-type = "shared" [set color yellow]
  ]
end



to-report heuristic [#Goal]
  ifelse (#Goal = nobody) [
    report 0
  ] [
    report [distance [localization] of myself] of #Goal
  ]
end

to-report A* [#Start #Goal]
  if (#Goal = nobody) [
    report false
  ]

  ask #Start [
    hatch-searchers 1 [
      set shape "circle"
      set color red
      set localization myself
      set memory (list ([who] of localization))
      set cost 0
      set total-expected-cost (cost + heuristic #Goal)
      set active? true
    ]
  ]

  while [not any? searchers with [localization = #Goal] and any? searchers with [active?]] [
    ask min-one-of (searchers with [active?]) [total-expected-cost] [
      set active? false
      let this-searcher self
      let Lorig localization
      ask ([link-neighbors] of Lorig) [
        let connection link-with Lorig
        let c ([cost] of this-searcher) + [link-length] of connection
        if not any? searchers-in-loc with [cost < c] [
          hatch-searchers 1 [
            set shape "circle"
            set color red
            set localization myself
            set memory lput ([who] of localization) ([memory] of this-searcher)
            set cost c
            set total-expected-cost (cost + heuristic #Goal)
            set active? true
            ask other searchers-in-loc [die]
          ]
        ]
      ]
    ]
  ]

  let res false
  if any? searchers with [localization = #Goal] [
    let lucky-searcher one-of searchers with [localization = #Goal]
    set res [memory] of lucky-searcher
  ]

  ask searchers [die]
  report res
end

to report-total-distances
  let total-car-distance sum [car-distance-traveled] of cars
  let total-ped-distance sum [ped-distance-traveled] of pedestrians
  let total-biker-distance sum [biker-distance-traveled] of bikers

  show (word "Total car distance traveled: " precision total-car-distance 2 " meters")
  show (word "Total pedestrian distance traveled: " precision total-ped-distance 2 " meters")
  show (word "Total biker distance traveled: " precision total-biker-distance 2 " meters")
end

to report-all-totals
  let car-distance sum [car-distance-traveled] of cars
  let ped-distance sum [ped-distance-traveled] of pedestrians
  let biker-distance sum [biker-distance-traveled] of bikers
  let switched switched-cars

  show (word "RUSH MODE = " rush-hour-mode)
  show (word "Car distance: " precision car-distance 2 " m")
  show (word "Pedestrian distance: " precision ped-distance 2 " m")
  show (word "Biker distance: " precision biker-distance 2 " m")
  show (word "Switched cars: " switched)
end

to-report searchers-in-loc
  report searchers with [localization = myself]
end

to highlight-path [path]
  let a reduce highlight path
end

to-report highlight [x-who y-who]
  let x turtle x-who  ;; Convert who number to a node
  let y turtle y-who  ;; Convert who number to a node
  ask x [
    ask link-with y [set color yellow set thickness pthk]
  ]
  report y-who
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
868
584
-1
-1
1.0
1
10
1
1
1
0
1
1
1
0
649
0
564
0
0
1
ticks
30.0

SWITCH
20
38
195
71
allow-mode-switch
allow-mode-switch
1
1
-1000

BUTTON
20
107
86
140
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
23
168
86
201
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
26
247
124
280
NIL
go-daytrip
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
29
301
186
334
NIL
morning-rush-hour
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
23
359
175
392
NIL
evening-rush-hour
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
25
419
158
452
NIL
report-all-totals
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
945
112
1050
145
load cached
import-world \"/Users/luigicolonna/rome_simulation.nlogo\"\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
