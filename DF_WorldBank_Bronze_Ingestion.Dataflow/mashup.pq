[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "Retrieve_WorldBank_data_DataDestination", IsNewTarget = true], Settings = [Kind = "Manual", AllowCreation = true, ColumnSettings = [Mappings = {[SourceColumnName = "country_code", DestinationColumnName = "country_code"], [SourceColumnName = "country_name", DestinationColumnName = "country_name"], [SourceColumnName = "country_iso3", DestinationColumnName = "country_iso3"], [SourceColumnName = "indicator_code", DestinationColumnName = "indicator_code"], [SourceColumnName = "indicator_name", DestinationColumnName = "indicator_name"], [SourceColumnName = "year", DestinationColumnName = "year"], [SourceColumnName = "gdp_usd", DestinationColumnName = "gdp_usd"], [SourceColumnName = "unit", DestinationColumnName = "unit"], [SourceColumnName = "observation_status", DestinationColumnName = "observation_status"], [SourceColumnName = "decimal_precision", DestinationColumnName = "decimal_precision"]}], DynamicSchema = true, UpdateMethod = [Kind = "Replace"], TypeSettings = [Kind = "Table"]]]}]
shared Retrieve_WorldBank_data = let
    Response = Json.Document(
        Web.Contents(
            "https://api.worldbank.org",
            [
                RelativePath = "v2/country/USA/indicator/NY.GDP.MKTP.CD",
                Query = [
                    format = "json",
                    per_page = "1000"
                ]
            ]
        )
    ),

    GDP = Response{1},

    SourceTable = Table.FromRecords(GDP),

    ExpandedIndicator = Table.ExpandRecordColumn(
        SourceTable,
        "indicator",
        {"id", "value"},
        {"indicator_code", "indicator_name"}
    ),

    ExpandedCountry = Table.ExpandRecordColumn(
        ExpandedIndicator,
        "country",
        {"id", "value"},
        {"country_code", "country_name"}
    ),

    RenamedColumns = Table.RenameColumns(
        ExpandedCountry,
        {
            {"countryiso3code", "country_iso3"},
            {"date", "year"},
            {"value", "gdp_usd"},
            {"obs_status", "observation_status"},
            {"decimal", "decimal_precision"}
        }
    ),

    ChangedTypes = Table.TransformColumnTypes(
        RenamedColumns,
        {
            {"indicator_code", type text},
            {"indicator_name", type text},
            {"country_code", type text},
            {"country_name", type text},
            {"country_iso3", type text},
            {"year", Int64.Type},
            {"gdp_usd", type number},
            {"unit", type text},
            {"observation_status", type text},
            {"decimal_precision", Int64.Type}
        }
    ),

    ReorderedColumns = Table.ReorderColumns(
        ChangedTypes,
        {
            "country_code",
            "country_name",
            "country_iso3",
            "indicator_code",
            "indicator_name",
            "year",
            "gdp_usd",
            "unit",
            "observation_status",
            "decimal_precision"
        }
    ),

    SortedRows = Table.Sort(
        ReorderedColumns,
        {{"year", Order.Ascending}}
    )

in
    SortedRows;
shared Retrieve_WorldBank_data_DataDestination = let
  Pattern = Lakehouse.Contents([HierarchicalNavigation = true, EnableVorder = true, OutputMetadataRefresh = false, CreateNavigationProperties = false, EnableFolding = false]),
  Navigation_1 = Pattern{[workspaceId = "794573d9-d83f-4efd-88de-1cd9be7176c5"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "223727be-3834-4320-a4b9-f4aa8b3e00d7"]}[Data],
  Navigation_3 = Navigation_2{[Id = "Bronze", ItemKind = "Schema"]}[Data],
  TableNavigation = Navigation_3{[Id = "WorldBank_GDP", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
