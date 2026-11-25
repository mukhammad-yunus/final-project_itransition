[DefaultOutputDestinationSettings = [DestinationDefinition = [Kind = "Reference", QueryName = "DefaultDestination", IsNewTarget = true], UpdateMethod = [Kind = "Replace"], DestinationTypeSettings = [Kind = "Table"]], StagingDefinition = [Kind = "FastCopy"]]
section Section1;
shared DefaultDestination = let
  Source = Lakehouse.Contents([HierarchicalNavigation = true, EnableVorder = true, OutputMetadataRefresh = true, CreateNavigationProperties = false, EnableFolding = false]),
  #"Navigation 1" = Source{[workspaceId = "794573d9-d83f-4efd-88de-1cd9be7176c5"]}[Data],
  #"Navigation 2" = #"Navigation 1"{[lakehouseId = "223727be-3834-4320-a4b9-f4aa8b3e00d7"]}[Data],
  #"Navigation 3" = #"Navigation 2"{[Id = "Bronze", ItemKind = "Schema"]}[Data]
in
  #"Navigation 3";
[Description = "OpenAQ API key used for API requests"]
shared ApiKey = "PLACEHOLDER_API_KEY" meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type text, DefaultValue = ""];
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "Bronze_OpenAQ_Locations_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared Bronze_OpenAQ_Locations = let
    NYC_BBox = "-74.2591,40.4774,-73.7004,40.9176",
    PageSize = 1000,
    IsPlaceholder = Text.StartsWith(Text.Upper(Text.Trim(ApiKey)), "PLACEHOLDER"),

    GetPage = (PageNumber as number) as list =>
        let
            Source = Json.Document(
                Web.Contents(
                    "https://api.openaq.org",
                    [
                        RelativePath = "v3/locations",
                        Query = [
                            bbox = NYC_BBox,
                            limit = Text.From(PageSize),
                            page = Text.From(PageNumber)
                        ],
                        Headers = [
                            #"X-API-Key" = ApiKey
                        ]
                    ]
                )
            ),
            Results = Record.FieldOrDefault(Source, "results", {})
        in
            Results,

    FinalTable =
        if IsPlaceholder then
            #table(
                type table [
                    id = Int64.Type,
                    name = text,
                    locality = text,
                    timezone = text,
                    isMobile = logical,
                    isMonitor = logical
                ],
                {}
            )
        else
            let
                Pages = List.Generate(
                    () => [Page = 1, Data = GetPage(1)],
                    each List.Count([Data]) > 0,
                    each [
                        Page = [Page] + 1,
                        Data = GetPage([Page] + 1)
                    ],
                    each [Data]
                ),
                AllLocations = List.Combine(Pages),
                RawTable = Table.FromRecords(AllLocations),
                ColumnNames = Table.ColumnNames(RawTable),
                NestedColumns = List.Select(
                    ColumnNames,
                    (ColumnName) =>
                        List.AnyTrue(
                            List.Transform(
                                Table.Column(RawTable, ColumnName),
                                each Value.Is(_, type record) or Value.Is(_, type list)
                            )
                        )
                ),
                ConvertNested = Table.TransformColumns(
                    RawTable,
                    List.Transform(
                        NestedColumns,
                        (ColumnName) =>
                            {
                                ColumnName,
                                (Value) =>
                                    if Value = null then
                                        null
                                    else
                                        Text.FromBinary(Json.FromValue(Value)),
                                type text
                            }
                    )
                ),
                TypedTable = Table.TransformColumnTypes(
                    ConvertNested,
                    {
                        {"id", Int64.Type},
                        {"name", type text},
                        {"locality", type text},
                        {"timezone", type text},
                        {"isMobile", type logical},
                        {"isMonitor", type logical}
                    }
                )
            in
                TypedTable
in
    FinalTable;
shared Bronze_OpenAQ_Locations_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = true, EnableVorder = true, OutputMetadataRefresh = false, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "794573d9-d83f-4efd-88de-1cd9be7176c5"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "223727be-3834-4320-a4b9-f4aa8b3e00d7"]}[Data],
  Navigation_3 = Navigation_2{[Id = "Bronze", ItemKind = "Schema"]}[Data],
  TableNavigation = Navigation_3{[Id = "OpenAQ_Locations", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
