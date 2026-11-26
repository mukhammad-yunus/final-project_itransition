[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
shared ApiKey = "PLACEHOLDER_API_KEY" meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type text, DefaultValue = ""];
shared DateFrom = "PLACEHOLDER_DATEFROM" meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type text, DefaultValue = ""];
shared DateTo = "PLACEHOLDER_DATETO" meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type text, DefaultValue = ""];
shared Locations_Source = let
  Source = Lakehouse.Contents(null),
  Navigation = Source{[workspaceId = "794573d9-d83f-4efd-88de-1cd9be7176c5"]}[Data],
  #"Navigation 1" = Navigation{[lakehouseId = "223727be-3834-4320-a4b9-f4aa8b3e00d7"]}[Data],
  #"Navigation 2" = #"Navigation 1"{[Id = "Bronze.OpenAQ_Locations", ItemKind = "Table"]}[Data]
in
  #"Navigation 2";
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "Bronze_OpenAQ_Measurements_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared Bronze_OpenAQ_Measurements = let
    PageSize = 1000,
    TargetPollutants = {"pm25", "no2", "o3"},

    CleanApiKey = Text.Trim(Text.From(ApiKey ?? ""), {" ", """"}),
    CleanDateFrom = Text.Trim(Text.From(DateFrom ?? ""), {" ", """"}),
    CleanDateTo = Text.Trim(Text.From(DateTo ?? ""), {" ", """"}),

    IsInvalidOrPlaceholder =
        CleanApiKey = "" or
        CleanDateFrom = "" or
        CleanDateTo = "" or
        Text.StartsWith(Text.Upper(CleanApiKey), "PLACEHOLDER") or
        Text.StartsWith(Text.Upper(CleanDateFrom), "PLACEHOLDER") or
        Text.StartsWith(Text.Upper(CleanDateTo), "PLACEHOLDER"),

    EmptyOutputTable = #table(
        type table [
            sensor_id = text,
            location_id = Int64.Type,
            location_name = text,
            locality = text,
            timezone = text,
            parameter = text,
            parameter_units = text,
            value = number,
            datetime_utc = text,
            datetime_local = text,
            datetime_to_utc = text,
            coverage_percent = number
        ],
        {}
    ),

    FinalTable =
        if IsInvalidOrPlaceholder then
            EmptyOutputTable
        else
            let
                Locations = Locations_Source,

                SelectedLocations = Table.SelectColumns(
                    Locations,
                    {"id", "name", "locality", "timezone", "sensors"}
                ),

                ParseSensors = Table.AddColumn(
                    SelectedLocations,
                    "ParsedSensors",
                    each
                        try Json.Document(
                            Text.ToBinary([sensors])
                        )
                        otherwise null
                ),

                SensorRows = List.Combine(
                    List.Transform(
                        Table.ToRecords(ParseSensors),
                        (LocationRecord) =>
                            let
                                SensorList =
                                    try LocationRecord[ParsedSensors]
                                    otherwise null,

                                Records =
                                    if SensorList = null then
                                        {}
                                    else
                                        List.Transform(
                                            SensorList,
                                            (SensorRecord) =>
                                                [
                                                    location_id = LocationRecord[id],
                                                    location_name = LocationRecord[name],
                                                    locality = LocationRecord[locality],
                                                    timezone = LocationRecord[timezone],
                                                    sensor_id =
                                                        try SensorRecord[id]
                                                        otherwise null,
                                                    parameter =
                                                        try SensorRecord[parameter][name]
                                                        otherwise null,
                                                    parameter_units =
                                                        try SensorRecord[parameter][units]
                                                        otherwise null
                                                ]
                                        )
                            in
                                Records
                    )
                ),

                SensorTable = Table.FromRecords(
                    SensorRows,
                    {
                        "location_id",
                        "location_name",
                        "locality",
                        "timezone",
                        "sensor_id",
                        "parameter",
                        "parameter_units"
                    },
                    MissingField.UseNull
                ),

                FilteredSensors = Table.SelectRows(
                    SensorTable,
                    each
                        [sensor_id] <> null
                        and [parameter] <> null
                        and List.Contains(
                            TargetPollutants,
                            Text.Lower(Text.From([parameter]))
                        )
                ),

                UniqueSensors = Table.Distinct(
                    FilteredSensors,
                    {"sensor_id"}
                ),

                BufferedSensors = Table.Buffer(UniqueSensors),

                SensorRecords = Table.ToRecords(BufferedSensors),

                MeasurementLists = List.Transform(
                    SensorRecords,
                    (SensorRecord) =>
                        let
                            SensorID = Text.From(SensorRecord[sensor_id]),

                            Response =
                                Web.Contents(
                                    "https://api.openaq.org",
                                    [
                                        RelativePath =
                                            "v3/sensors/"
                                            & SensorID
                                            & "/hours",

                                        Query = [
                                            datetime_from = CleanDateFrom,
                                            datetime_to = CleanDateTo,
                                            limit = Text.From(PageSize),
                                            page = "1"
                                        ],

                                        Headers = [
                                            #"X-API-Key" = CleanApiKey
                                        ],

                                        Timeout = #duration(0, 0, 0, 60)
                                    ]
                                ),

                            JsonResponse = Json.Document(Response),

                            Data = Record.FieldOrDefault(JsonResponse, "results", {}),

                            Rows = List.Transform(
                                Data,
                                (Measurement) =>
                                    [
                                        sensor_id = SensorID,
                                        location_id = SensorRecord[location_id],
                                        location_name = SensorRecord[location_name],
                                        locality = SensorRecord[locality],
                                        timezone = SensorRecord[timezone],
                                        parameter = SensorRecord[parameter],
                                        parameter_units = SensorRecord[parameter_units],
                                        value =
                                            try Measurement[value]
                                            otherwise null,
                                        datetime_utc =
                                            try Measurement[period][datetimeFrom][utc]
                                            otherwise null,
                                        datetime_local =
                                            try Measurement[period][datetimeFrom][local]
                                            otherwise null,
                                        datetime_to_utc =
                                            try Measurement[period][datetimeTo][utc]
                                            otherwise null,
                                        coverage_percent =
                                            try Measurement[coverage][percentComplete]
                                            otherwise null
                                    ]
                            )
                        in
                            Rows
                ),

                AllMeasurementRecords = List.Combine(
                    MeasurementLists
                ),

                OutputTable = Table.FromRecords(
                    AllMeasurementRecords,
                    {
                        "sensor_id",
                        "location_id",
                        "location_name",
                        "locality",
                        "timezone",
                        "parameter",
                        "parameter_units",
                        "value",
                        "datetime_utc",
                        "datetime_local",
                        "datetime_to_utc",
                        "coverage_percent"
                    },
                    MissingField.UseNull
                ),

                TypedTable = Table.TransformColumnTypes(
                    OutputTable,
                    {
                        {"sensor_id", type text},
                        {"location_id", Int64.Type},
                        {"location_name", type text},
                        {"locality", type text},
                        {"timezone", type text},
                        {"parameter", type text},
                        {"parameter_units", type text},
                        {"value", type number},
                        {"datetime_utc", type text},
                        {"datetime_local", type text},
                        {"datetime_to_utc", type text},
                        {"coverage_percent", type number}
                    }
                ),

                #"Sorted rows" = Table.Sort(TypedTable, {{"sensor_id", Order.Descending}})
            in
                #"Sorted rows"
in
    FinalTable;
shared Bronze_OpenAQ_Measurements_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = true, EnableVorder = true, OutputMetadataRefresh = false, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "794573d9-d83f-4efd-88de-1cd9be7176c5"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "223727be-3834-4320-a4b9-f4aa8b3e00d7"]}[Data],
  Navigation_3 = Navigation_2{[Id = "Bronze", ItemKind = "Schema"]}[Data],
  TableNavigation = Navigation_3{[Id = "OpenAQ_Measurements", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
